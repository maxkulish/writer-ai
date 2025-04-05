# Caching Implementation Strategy for WriterAI Rust Backend

After analyzing the WriterAI codebase and evaluating various caching options, this document outlines a comprehensive caching strategy for the rust_service component to improve performance of writing checks while ensuring offline functionality.

## Current Implementation Analysis

The current implementation processes text through the following flow:
1. User sends text to the `/process` endpoint
2. The handler calls `query_llm` with the text
3. `query_llm` formats the request based on the LLM provider (Ollama or OpenAI)
4. The request is sent to the LLM API
5. The response is parsed and returned

Each request results in a new LLM API call, even for identical text, which is inefficient and requires network connectivity.

## Caching Strategy

### 1. Endpoints/Operations to Cache

The primary target for caching is the `query_llm` function in `src/llm.rs`, which handles all LLM interactions. By implementing caching at this level, we can:
- Intercept requests before they reach external LLM APIs
- Return cached results for identical inputs
- Maintain the existing API contract with the rest of the application

### 2. Recommended Caching Solution: `sled`

After evaluating multiple options, we recommend using **`sled`** as the embedded key-value store:

**Rationale:**
- **Pure Rust implementation**: Aligns with the codebase's language
- **Embeddable**: No external service required, runs within the process
- **Persistence**: Data stored in a single file/directory, ideal for local caching
- **Performance**: High-performance, optimized for this exact use case
- **Transactional & crash-safe**: Ensures data integrity
- **Concurrency**: Handles concurrent access efficiently
- **Offline capability**: Works entirely locally without external dependencies
- **Simplicity**: Minimal setup compared to other database options

**Alternative Options Considered:**
1. **SQLite with Rusqlite**: Good option but requires more setup and schema management
2. **In-memory cache (e.g., moka, dashmap)**: Fast but non-persistent across restarts
3. **File-based (manual JSON/TOML files)**: Complex to manage efficiently
4. **External DB (Redis)**: Requires running a separate service locally

### 3. Cache Key Structure

To ensure cache correctness, the key should represent all factors influencing the LLM output:

**Key Components:**
- Input Text (`req.text`)
- Model Name (`config.model_name`)
- Prompt Template (`config.prompt_template` if used)
- Relevant LLM Parameters (if they significantly alter deterministic output)

**Implementation:**
```rust
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

fn calculate_hash<T: Hash>(t: &T) -> u64 {
    let mut s = DefaultHasher::new();
    t.hash(&mut s);
    s.finish()
}

// Inside the handler or cache module
let model_name = &config.model_name;
let template_hash = config.prompt_template.as_ref()
    .map(|t| calculate_hash(t))
    .unwrap_or(0);
let input_text = &req.text;

let combined_key_data = format!("{}|{}|{}", model_name, template_hash, input_text);
let cache_key_hash = calculate_hash(&combined_key_data);
let cache_key_bytes = cache_key_hash.to_be_bytes(); // Use bytes for sled key
```

### 4. TTL and Cache Management

**Cache Expiration:**
- Default TTL: 30 days (configurable)
- Configuration via config.toml:
  ```toml
  [cache]
  enabled = true
  ttl_days = 30
  max_size_mb = 100
  ```
- Periodic cleanup of expired entries (on service startup)

**Cache Value Structure:**
- Store the response `String` directly in `sled` as UTF-8 bytes
- Include metadata (creation timestamp, expiration timestamp) in the stored value

### 5. Implementation Approach

#### Step 1: Add Dependencies
```toml
# In Cargo.toml
[dependencies]
sled = "0.34"
```

#### Step 2: Create Cache Module
Create a new `cache.rs` file:

```rust
use crate::errors::AppError;
use sled::{Db, IVec};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone)]
pub struct CacheConfig {
    pub enabled: bool,
    pub ttl_days: u64,
    pub max_size_mb: u64,
}

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

pub struct CacheManager {
    db: Db,
    config: CacheConfig,
}

impl CacheManager {
    pub fn new<P: AsRef<Path>>(path: P, config: CacheConfig) -> Result<Self, AppError> {
        let db = sled::open(path)
            .map_err(|e| AppError::CacheError(format!("Failed to open cache database: {}", e)))?;
        
        let manager = Self { db, config };
        
        // Run cleanup on startup if cache is enabled
        if config.enabled {
            manager.cleanup_expired()?;
        }
        
        Ok(manager)
    }
    
    pub fn generate_key(text: &str, model: &str, prompt_template_hash: u64) -> Vec<u8> {
        let combined = format!("{}|{}|{}", model, prompt_template_hash, text);
        
        let mut hasher = DefaultHasher::new();
        combined.hash(&mut hasher);
        let hash = hasher.finish();
        
        hash.to_be_bytes().to_vec()
    }
    
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
                    Ok(None)
                } else {
                    Ok(Some(entry.response))
                }
            },
            Ok(None) => Ok(None),
            Err(e) => Err(AppError::CacheError(format!("Cache lookup failed: {}", e))),
        }
    }
    
    pub fn store(&self, text: &str, response: &str, model: &str, prompt_template_hash: u64) -> Result<(), AppError> {
        if !self.config.enabled {
            return Ok(());
        }
        
        let key = Self::generate_key(text, model, prompt_template_hash);
        let entry = CacheEntry::new(response.to_string(), self.config.ttl_days);
        
        self.db.insert(key, entry.to_bytes())
            .map_err(|e| AppError::CacheError(format!("Failed to store in cache: {}", e)))?;
        
        Ok(())
    }
    
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
    
    pub fn clear(&self) -> Result<(), AppError> {
        self.db.clear()
            .map_err(|e| AppError::CacheError(format!("Failed to clear cache: {}", e)))?;
        
        Ok(())
    }
}
```

#### Step 3: Update AppConfig

Modify `src/config.rs` to include cache configuration:

```rust
// In config.rs
#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
    // ... existing fields
    #[serde(default)]
    pub cache: CacheConfig,
}

#[derive(Debug, Deserialize, Clone)]
pub struct CacheConfig {
    #[serde(default = "default_cache_enabled")]
    pub enabled: bool,
    
    #[serde(default = "default_cache_ttl_days")]
    pub ttl_days: u64,
    
    #[serde(default = "default_cache_max_size_mb")]
    pub max_size_mb: u64,
}

fn default_cache_enabled() -> bool {
    true
}

fn default_cache_ttl_days() -> u64 {
    30
}

fn default_cache_max_size_mb() -> u64 {
    100
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            enabled: default_cache_enabled(),
            ttl_days: default_cache_ttl_days(),
            max_size_mb: default_cache_max_size_mb(),
        }
    }
}
```

#### Step 4: Initialize Cache in main.rs

```rust
// In main.rs
use std::sync::Arc;
use std::path::PathBuf;
use crate::cache::CacheManager;

// Inside main function
fn main() -> Result<(), AppError> {
    // ... existing code
    
    // Initialize the cache
    let cache_dir = dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("writer_ai");
    
    std::fs::create_dir_all(&cache_dir)
        .map_err(|e| AppError::ConfigError(format!("Failed to create cache directory: {}", e)))?;
    
    let cache_path = cache_dir.join("response_cache.sled");
    let cache_manager = Arc::new(CacheManager::new(
        cache_path, 
        app_config.cache.clone()
    )?);
    
    // ... modify router setup to include cache_manager in State
    let app = Router::new()
        .route("/process", post(process_text_handler))
        // ... other routes
        .with_state((Arc::clone(&app_config), Arc::clone(&client), Arc::clone(&cache_manager)));
    
    // ... rest of main function
}
```

#### Step 5: Modify Handler to Use Cache

Update `src/http.rs` to use the cache:

```rust
// In http.rs
use crate::cache::CacheManager;
use std::sync::Arc;

pub async fn process_text_handler(
    State((config, client, cache_manager)): State<(Arc<AppConfig>, Arc<Client>, Arc<CacheManager>)>,
    Json(req): Json<ProcessRequest>,
) -> Result<Json<ProcessResponse>, AppError> {
    let prompt_template_hash = config.prompt_template
        .as_ref()
        .map(|template| {
            let mut hasher = std::collections::hash_map::DefaultHasher::new();
            template.hash(&mut hasher);
            hasher.finish()
        })
        .unwrap_or(0);
    
    // Try cache lookup first
    match cache_manager.lookup(&req.text, &config.model_name, prompt_template_hash) {
        Ok(Some(cached_response)) => {
            log::info!("Cache hit for request");
            return Ok(Json(ProcessResponse {
                response: cached_response,
            }));
        },
        Ok(None) => {
            log::info!("Cache miss, querying LLM");
        },
        Err(e) => {
            log::warn!("Cache lookup error: {}", e);
            // Continue with LLM query on cache error
        }
    }
    
    // Existing LLM query logic
    let llm_response = query_llm(&req.text, &config, &client).await?;
    
    // Store in cache
    if let Err(e) = cache_manager.store(&req.text, &llm_response, &config.model_name, prompt_template_hash) {
        log::warn!("Failed to store in cache: {}", e);
    }
    
    Ok(Json(ProcessResponse {
        response: llm_response,
    }))
}
```

#### Step 6: Update Error Module

Add cache-related errors to `src/errors.rs`:

```rust
// In errors.rs
#[derive(Debug)]
pub enum AppError {
    // ... existing variants
    CacheError(String),
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            // ... existing variants
            AppError::CacheError(msg) => write!(f, "Cache error: {}", msg),
        }
    }
}
```

## Implementation Steps

1. **Create Cache Module**:
   - Implement `cache.rs` with `CacheManager` and related functionality
   - Add serialization/deserialization for cache entries

2. **Update AppConfig**:
   - Add cache configuration options to `config.rs`
   - Update config.toml template with cache section

3. **Modify Main Application**:
   - Initialize cache in `main.rs`
   - Set up proper cache directory path
   - Include cache manager in shared application state

4. **Integrate with HTTP Handler**:
   - Modify `process_text_handler` to use cache before querying LLM
   - Store successful responses in cache
   - Handle cache errors gracefully

5. **Add Error Handling**:
   - Update `AppError` to include cache-related errors
   - Implement proper error handling for cache operations

6. **Testing**:
   - Create integration tests for cache functionality
   - Verify cache hits/misses work correctly
   - Test cache expiration logic

## Performance Expectations

- **Cache Hit Rate**: 30-50% in typical usage scenarios
- **Response Time**: 5-20ms for cache hits vs. 1-5s for LLM API calls
- **Storage Impact**: Approximately 1MB per 1000 cached entries (varies with text length)

## Future Enhancements

1. **Advanced Cache Invalidation**:
   - Add API endpoint to manually clear cache
   - Implement selective cache invalidation based on model updates

2. **Size-Based Eviction**:
   - Implement LRU eviction when max cache size is reached
   - Track total cache size and manage accordingly

3. **Cache Analytics**:
   - Track and report cache hit/miss rates
   - Provide cache statistics via API endpoint

4. **Text Normalization**:
   - Implement input text normalization for better cache hit rates
   - Handle minor text differences (whitespace, punctuation)

This caching strategy provides significant performance benefits for repeated writing checks while maintaining the ability to work offline on the user's laptop.