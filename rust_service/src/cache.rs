use crate::errors::AppError;
use serde::Deserialize;
use sled::Db;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::{debug, info};

/// Cache configuration options
#[derive(Debug, Clone, Deserialize)]
pub struct CacheConfig {
    pub enabled: bool,
    pub ttl_days: u64,
    pub max_size_mb: u64,
}

/// The data stored in the cache
pub struct CacheEntry {
    pub response: String,
    pub created_at: u64,
    pub expires_at: u64,
}

impl CacheEntry {
    pub fn new(response: String, ttl_days: u64) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        let expires_at = now + (ttl_days * 24 * 60 * 60);
        
        Self {
            response,
            created_at: now,
            expires_at,
        }
    }
    
    pub fn to_bytes(&self) -> Vec<u8> {
        // Simple serialization: combine fields with delimiters
        let data = format!(
            "{}|{}|{}", 
            self.response, 
            self.created_at, 
            self.expires_at
        );
        data.into_bytes()
    }
    
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, AppError> {
        let data = String::from_utf8(bytes.to_vec())
            .map_err(|e| AppError::CacheError(format!("Failed to deserialize cache entry: {}", e)))?;
        
        let parts: Vec<&str> = data.splitn(3, '|').collect();
        if parts.len() != 3 {
            return Err(AppError::CacheError("Invalid cache entry format".to_string()));
        }
        
        let response = parts[0].to_string();
        let created_at = parts[1].parse::<u64>()
            .map_err(|e| AppError::CacheError(format!("Invalid created_at timestamp: {}", e)))?;
        let expires_at = parts[2].parse::<u64>()
            .map_err(|e| AppError::CacheError(format!("Invalid expires_at timestamp: {}", e)))?;
        
        Ok(Self {
            response,
            created_at,
            expires_at,
        })
    }
    
    pub fn is_expired(&self) -> bool {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        self.expires_at < now
    }
}

/// Manager for the sled-based response cache
pub struct CacheManager {
    db: Db,
    config: CacheConfig,
}

impl CacheManager {
    /// Create a new cache manager with the given configuration
    pub fn new<P: AsRef<Path>>(path: P, config: CacheConfig) -> Result<Self, AppError> {
        let db = sled::open(path)
            .map_err(|e| AppError::CacheError(format!("Failed to open cache database: {}", e)))?;
        
        let manager = Self { db, config: config.clone() };
        
        // Run cleanup on startup if cache is enabled
        if config.enabled {
            let count = manager.cleanup_expired()?;
            if count > 0 {
                info!("Removed {} expired cache entries during startup", count);
            }
        }
        
        Ok(manager)
    }
    
    /// Generate a cache key from the input text, model, and prompt template hash
    pub fn generate_key(text: &str, model: &str, prompt_template_hash: u64) -> Vec<u8> {
        let combined = format!("{}|{}|{}", model, prompt_template_hash, text);
        
        let mut hasher = DefaultHasher::new();
        combined.hash(&mut hasher);
        let hash = hasher.finish();
        
        hash.to_be_bytes().to_vec()
    }
    
    /// Lookup a cached response for the given input
    pub fn lookup(&self, text: &str, model: &str, prompt_template_hash: u64) -> Result<Option<String>, AppError> {
        if !self.config.enabled {
            return Ok(None);
        }
        
        let key = Self::generate_key(text, model, prompt_template_hash);
        
        match self.db.get(&key) {
            Ok(Some(ivec)) => {
                let entry = CacheEntry::from_bytes(&ivec)?;
                
                if entry.is_expired() {
                    // Remove expired entry
                    let _ = self.db.remove(&key);
                    debug!("Removed expired cache entry");
                    Ok(None)
                } else {
                    debug!("Cache hit for text input");
                    Ok(Some(entry.response))
                }
            },
            Ok(None) => {
                debug!("Cache miss for text input");
                Ok(None)
            },
            Err(e) => Err(AppError::CacheError(format!("Cache lookup failed: {}", e))),
        }
    }
    
    /// Store a response in the cache
    pub fn store(&self, text: &str, response: &str, model: &str, prompt_template_hash: u64) -> Result<(), AppError> {
        if !self.config.enabled {
            return Ok(());
        }
        
        let key = Self::generate_key(text, model, prompt_template_hash);
        let entry = CacheEntry::new(response.to_string(), self.config.ttl_days);
        
        self.db.insert(key, entry.to_bytes())
            .map_err(|e| AppError::CacheError(format!("Failed to store in cache: {}", e)))?;
        
        debug!("Stored response in cache");
        Ok(())
    }
    
    /// Clean up expired cache entries
    pub fn cleanup_expired(&self) -> Result<usize, AppError> {
        if !self.config.enabled {
            return Ok(0);
        }
        
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        let mut removed_count = 0;
        
        for item in self.db.iter() {
            match item {
                Ok((key, value)) => {
                    match CacheEntry::from_bytes(&value) {
                        Ok(entry) if entry.expires_at < now => {
                            if let Ok(_) = self.db.remove(key) {
                                removed_count += 1;
                            }
                        },
                        _ => continue,
                    }
                },
                Err(_) => continue,
            }
        }
        
        Ok(removed_count)
    }
    
    /// Clear the entire cache
    #[allow(dead_code)]
    pub fn clear(&self) -> Result<(), AppError> {
        self.db.clear()
            .map_err(|e| AppError::CacheError(format!("Failed to clear cache: {}", e)))?;
        
        info!("Cache cleared");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    
    #[test]
    fn test_cache_entry_serialization() {
        let entry = CacheEntry::new("Test response".to_string(), 30);
        let bytes = entry.to_bytes();
        let deserialized = CacheEntry::from_bytes(&bytes).unwrap();
        
        assert_eq!(entry.response, deserialized.response);
        assert_eq!(entry.created_at, deserialized.created_at);
        assert_eq!(entry.expires_at, deserialized.expires_at);
    }
    
    #[test]
    fn test_cache_is_expired() {
        // Test non-expired entry
        let entry = CacheEntry::new("Test response".to_string(), 30);
        assert!(!entry.is_expired());
        
        // Test expired entry (created in the past)
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        let mut expired_entry = CacheEntry::new("Expired response".to_string(), 30);
        expired_entry.created_at = now - 60 * 60 * 24 * 31; // 31 days ago
        expired_entry.expires_at = now - 60 * 60 * 24; // 1 day ago
        
        assert!(expired_entry.is_expired());
    }
    
    #[test]
    fn test_cache_manager() {
        // Create a temporary directory for the test database
        let temp_dir = TempDir::new().unwrap();
        let cache_path = temp_dir.path().join("test_cache.sled");
        
        // Create cache config
        let config = CacheConfig {
            enabled: true,
            ttl_days: 30,
            max_size_mb: 100,
        };
        
        // Create cache manager
        let cache_manager = CacheManager::new(&cache_path, config).unwrap();
        
        // Test storing and retrieving data
        let text = "Test input text";
        let model = "test-model";
        let prompt_hash = 12345u64;
        let response = "Test response";
        
        // Store the response
        cache_manager.store(text, response, model, prompt_hash).unwrap();
        
        // Lookup the response
        let cached_response = cache_manager.lookup(text, model, prompt_hash).unwrap();
        
        assert_eq!(cached_response, Some(response.to_string()));
        
        // Test with different text
        let different_text = "Different text";
        let cached_response = cache_manager.lookup(different_text, model, prompt_hash).unwrap();
        
        assert_eq!(cached_response, None);
        
        // Test with different model
        let different_model = "different-model";
        let cached_response = cache_manager.lookup(text, different_model, prompt_hash).unwrap();
        
        assert_eq!(cached_response, None);
        
        // Test with different prompt hash
        let different_hash = 54321u64;
        let cached_response = cache_manager.lookup(text, model, different_hash).unwrap();
        
        assert_eq!(cached_response, None);
        
        // Test cache clear
        cache_manager.clear().unwrap();
        let cached_response = cache_manager.lookup(text, model, prompt_hash).unwrap();
        
        assert_eq!(cached_response, None);
    }
    
    #[test]
    fn test_disabled_cache() {
        // Create a temporary directory for the test database
        let temp_dir = TempDir::new().unwrap();
        let cache_path = temp_dir.path().join("test_cache.sled");
        
        // Create cache config with cache disabled
        let config = CacheConfig {
            enabled: false,
            ttl_days: 30,
            max_size_mb: 100,
        };
        
        // Create cache manager
        let cache_manager = CacheManager::new(&cache_path, config).unwrap();
        
        // Test storing and retrieving data with disabled cache
        let text = "Test input text";
        let model = "test-model";
        let prompt_hash = 12345u64;
        let response = "Test response";
        
        // Store the response (should be a no-op)
        cache_manager.store(text, response, model, prompt_hash).unwrap();
        
        // Lookup the response (should return None)
        let cached_response = cache_manager.lookup(text, model, prompt_hash).unwrap();
        
        assert_eq!(cached_response, None);
    }
}