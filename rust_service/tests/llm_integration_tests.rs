use writer_ai_rust_service::config::AppConfig;
use writer_ai_rust_service::http::{process_text_handler, ProcessRequest};
use writer_ai_rust_service::cache::{CacheManager, CacheConfig};
use axum::extract::State;
use axum::Json;
use reqwest::Client;
use std::sync::Arc;
use tempfile::TempDir;
use tokio::fs;
use std::path::{Path, PathBuf};
use chrono::Utc;

// Define test data module directly here
mod llm_test_data {
    use chrono::{DateTime, Utc};
    use serde::{Deserialize, Serialize};
    use std::fs;
    use std::path::{Path, PathBuf};

    // Core test data structure for collecting results
    #[derive(Debug, Serialize, Deserialize, Clone)]
    pub struct TestResult {
        // Test metadata
        pub test_id: String,
        pub input: String,
        pub expected: Option<String>,
        pub model_output: String,
        pub model: String,
        pub timestamp: DateTime<Utc>,
        
        // Metrics
        pub metrics: Metrics,
    }

    // Separate metrics structure for cleaner organization
    #[derive(Debug, Serialize, Deserialize, Clone, Default)]
    pub struct Metrics {
        pub latency_ms: u64,
        pub edit_distance: Option<usize>,
        pub semantic_similarity: Option<f64>,
        pub grammar_check_score: Option<f64>,
    }

    // Configuration structure for test parameters
    #[derive(Deserialize)]
    pub struct TestConfig {
        pub sentences: Vec<TestSentence>,
        // Removed unused fields: test_run_id, export_formats, metrics_to_collect
    }

    // Test sentence structure with expected corrections
    #[derive(Debug, Deserialize, Clone)]
    pub struct TestSentence {
        pub id: String,
        pub text: String,
        pub expected: Option<String>,
    }

    // Helper functions for test data management
    pub fn save_test_result(result: &TestResult, base_dir: &Path) -> std::io::Result<PathBuf> {
        // Create directory for model if it doesn't exist
        let model_dir = base_dir.join(result.model.replace("/", "_"));
        fs::create_dir_all(&model_dir)?;
        
        // Create JSON file path
        let file_name = format!("{}.json", result.test_id);
        let file_path = model_dir.join(file_name);
        
        // Serialize and save
        let json_data = serde_json::to_string_pretty(result)?;
        fs::write(&file_path, json_data)?;
        
        Ok(file_path)
    }

    // Calculate edit distance between two strings
    pub fn calculate_edit_distance(s1: &str, s2: &str) -> usize {
        let s1: Vec<char> = s1.chars().collect();
        let s2: Vec<char> = s2.chars().collect();
        
        let m = s1.len();
        let n = s2.len();
        
        // Handle empty string cases
        if m == 0 { return n; }
        if n == 0 { return m; }
        
        // Create a distance matrix
        let mut dp = vec![vec![0; n+1]; m+1];
        
        // Initialize first row and column
        for i in 0..=m {
            dp[i][0] = i;
        }
        
        for j in 0..=n {
            dp[0][j] = j;
        }
        
        // Fill the matrix
        for i in 1..=m {
            for j in 1..=n {
                // Calculate cost of substitution
                let cost = if s1[i-1] == s2[j-1] { 0 } else { 1 };
                
                // Calculate minimum of deletion, insertion, and substitution
                dp[i][j] = (dp[i-1][j] + 1)  // Deletion
                    .min(dp[i][j-1] + 1)     // Insertion
                    .min(dp[i-1][j-1] + cost); // Substitution
            }
        }
        
        // Return the edit distance
        dp[m][n]
    }

    // Export results to CSV format
    pub fn export_to_csv(results: &[TestResult], file_path: &Path) -> std::io::Result<()> {
        let mut csv_data = String::new();
        
        // Create header row
        csv_data.push_str("test_id,model,timestamp,latency_ms,edit_distance,semantic_similarity,grammar_check_score\n");
        
        // Add data rows
        for result in results {
            csv_data.push_str(&format!(
                "{},{},{},{},{},{},{}\n",
                result.test_id,
                result.model,
                result.timestamp.to_rfc3339(),
                result.metrics.latency_ms,
                result.metrics.edit_distance.unwrap_or(0),
                result.metrics.semantic_similarity.unwrap_or(0.0),
                result.metrics.grammar_check_score.unwrap_or(0.0)
            ));
        }
        
        // Write to file
        fs::write(file_path, csv_data)
    }

    // Load test configuration from TOML file
    pub fn load_test_config(config_path: &Path) -> Result<TestConfig, String> {
        let config_str = fs::read_to_string(config_path)
            .map_err(|e| format!("Failed to read test config file: {}", e))?;
        
        let config: TestConfig = toml::from_str(&config_str)
            .map_err(|e| format!("Failed to parse test config TOML: {}", e))?;
        
        Ok(config)
    }

    // Generate a unique test run ID
    pub fn generate_test_run_id() -> String {
        use rand::{thread_rng, Rng};
        use rand::distributions::Alphanumeric;
        
        let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S");
        let random_suffix: String = thread_rng()
            .sample_iter(&Alphanumeric)
            .take(6)
            .map(char::from)
            .collect();
        
        format!("run_{}_{}", timestamp, random_suffix)
    }
}

// Define metrics module
mod llm_metrics {
    use std::time::Duration;
    use strsim::jaro_winkler;

    // Semantic similarity scoring using Jaro-Winkler distance
    pub fn calculate_semantic_similarity(s1: &str, s2: &str) -> f64 {
        jaro_winkler(s1, s2)
    }

    // Grammar check scoring (simplified simulation - would be replaced with actual grammar checker)
    pub fn calculate_grammar_score(text: &str) -> f64 {
        // This is a placeholder that would be replaced with a real grammar checking library
        // For now, just returning a score based on some simple heuristics
        
        // Count common grammar issues (very simplified)
        let lowercase_text = text.to_lowercase();
        let mut issues = 0;
        
        // Check for double spaces
        if text.contains("  ") {
            issues += 1;
        }
        
        // Check for missing periods at end
        if !text.trim().ends_with('.') && !text.trim().ends_with('?') && !text.trim().ends_with('!') {
            issues += 1;
        }
        
        // Check for common grammar errors (very basic checks)
        let error_phrases = [
            " i ", // Lowercase "I"
            "dont", "cant", "wont", "isnt", // Missing apostrophes
            "your welcome", "its a", // Common your/you're and its/it's errors
            "alot", "alltogether", // Common misspellings
        ];
        
        for phrase in error_phrases.iter() {
            if lowercase_text.contains(phrase) {
                issues += 1;
            }
        }
        
        // Calculate score (1.0 is perfect, 0.0 is worst)
        // Max 5 issues for normalization
        let max_issues = 5;
        let normalized_issues = issues.min(max_issues);
        1.0 - (normalized_issues as f64 / max_issues as f64)
    }

    // Timing metrics
    pub struct TimingMetrics {
        pub start_time: std::time::Instant,
        pub end_time: Option<std::time::Instant>,
    }

    impl TimingMetrics {
        pub fn new() -> Self {
            Self {
                start_time: std::time::Instant::now(),
                end_time: None,
            }
        }
        
        pub fn stop(&mut self) {
            self.end_time = Some(std::time::Instant::now());
        }
        
        pub fn duration(&self) -> Duration {
            match self.end_time {
                Some(end) => end.duration_since(self.start_time),
                None => std::time::Instant::now().duration_since(self.start_time),
            }
        }
        
        pub fn milliseconds(&self) -> u64 {
            let duration = self.duration();
            duration.as_secs() * 1000 + duration.subsec_millis() as u64
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        
        #[test]
        fn test_semantic_similarity() {
            // Test perfect match
            assert_eq!(calculate_semantic_similarity("hello world", "hello world"), 1.0);
            
            // Test similar strings
            let similarity = calculate_semantic_similarity(
                "The cat sat on the mat", 
                "The fluffy cat sat on the mat"
            );
            assert!(similarity > 0.8); // Should be quite similar
            
            // Test completely different strings
            let similarity = calculate_semantic_similarity(
                "The cat sat on the mat", 
                "Programming in Rust is fun"
            );
            assert!(similarity < 0.5); // Should be very different
        }
        
        #[test]
        fn test_grammar_score() {
            // Test perfect grammar
            let score = calculate_grammar_score("This is a well-formed sentence with good grammar.");
            assert!(score > 0.9);
            
            // Test bad grammar
            let score = calculate_grammar_score("i dont think its a good idea alot of the time");
            assert!(score < 0.5);
        }
        
        #[test]
        fn test_timing_metrics() {
            let mut timing = TimingMetrics::new();
            
            // Sleep for a small amount of time
            std::thread::sleep(Duration::from_millis(10));
            
            timing.stop();
            
            // Verify timing is at least 10ms
            assert!(timing.milliseconds() >= 10);
        }
    }
}

// Define analysis module
mod llm_analysis {
    use chrono::{DateTime, Utc};
    use serde::Serialize;
    use std::collections::HashMap;
    use std::fs;
    use std::io;
    use std::path::{Path, PathBuf};

    use crate::llm_test_data::TestResult;

    /// Model comparison summary
    #[derive(Debug, Serialize)]
    pub struct ModelComparison {
        pub model_name: String,
        pub test_count: usize,
        pub success_count: usize,
        pub error_count: usize,
        pub avg_latency_ms: f64,
        pub avg_edit_distance: f64,
        pub avg_semantic_similarity: f64,
        pub avg_grammar_score: f64,
    }

    /// Test run summary
    #[derive(Debug, Serialize)]
    pub struct TestRunSummary {
        pub run_id: String,
        pub timestamp: DateTime<Utc>,
        pub test_count: usize,
        pub model_count: usize,
        pub models: Vec<ModelComparison>,
    }

    /// Analyze test results and generate summary
    pub fn analyze_test_run(results: &[TestResult], run_id: &str) -> TestRunSummary {
        let mut model_stats: HashMap<String, Vec<&TestResult>> = HashMap::new();
        
        // Group results by model
        for result in results {
            model_stats.entry(result.model.clone())
                .or_default()
                .push(result);
        }
        
        // Generate model comparisons
        let models = model_stats.iter()
            .map(|(model_name, results)| {
                let test_count = results.len();
                let error_count = results.iter()
                    .filter(|r| r.model_output.starts_with("ERROR:"))
                    .count();
                let success_count = test_count - error_count;
                
                // Filter successful results for metric calculations
                let successful_results: Vec<&TestResult> = results.iter()
                    .filter(|r| !r.model_output.starts_with("ERROR:"))
                    .copied()
                    .collect();
                
                // Calculate averages
                let avg_latency_ms = if !successful_results.is_empty() {
                    successful_results.iter()
                        .map(|r| r.metrics.latency_ms as f64)
                        .sum::<f64>() / successful_results.len() as f64
                } else {
                    0.0
                };
                
                let avg_edit_distance = if !successful_results.is_empty() {
                    successful_results.iter()
                        .filter_map(|r| r.metrics.edit_distance.map(|d| d as f64))
                        .sum::<f64>() / successful_results.len() as f64
                } else {
                    0.0
                };
                
                let avg_semantic_similarity = if !successful_results.is_empty() {
                    successful_results.iter()
                        .filter_map(|r| r.metrics.semantic_similarity)
                        .sum::<f64>() / successful_results.len() as f64
                } else {
                    0.0
                };
                
                let avg_grammar_score = if !successful_results.is_empty() {
                    successful_results.iter()
                        .filter_map(|r| r.metrics.grammar_check_score)
                        .sum::<f64>() / successful_results.len() as f64
                } else {
                    0.0
                };
                
                ModelComparison {
                    model_name: model_name.clone(),
                    test_count,
                    success_count,
                    error_count,
                    avg_latency_ms,
                    avg_edit_distance,
                    avg_semantic_similarity,
                    avg_grammar_score,
                }
            })
            .collect();
        
        // Create overall summary
        TestRunSummary {
            run_id: run_id.to_string(),
            timestamp: Utc::now(),
            test_count: results.len(),
            model_count: model_stats.len(),
            models,
        }
    }

    // Save analysis results to JSON file
    pub fn save_analysis(summary: &TestRunSummary, results_dir: &Path) -> io::Result<PathBuf> {
        let file_path = results_dir.join("analysis.json");
        let json_content = serde_json::to_string_pretty(summary)?;
        fs::write(&file_path, json_content)?;
        Ok(file_path)
    }

    // Generate HTML report from test results
    pub fn generate_html_report(summary: &TestRunSummary, results: &[TestResult], results_dir: &Path) -> io::Result<PathBuf> {
        // Generate HTML content
        let mut html = String::from(r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LLM Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        h1, h2, h3 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { padding: 12px 15px; border: 1px solid #ddd; text-align: left; }
        th { background-color: #f2f2f2; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .metric-good { color: green; }
        .metric-medium { color: orange; }
        .metric-poor { color: red; }
        .test-container { border: 1px solid #ddd; padding: 15px; margin-bottom: 20px; border-radius: 5px; }
        .model-response { background-color: #f5f5f5; padding: 10px; border-radius: 5px; margin-top: 10px; }
        .error-response { background-color: #ffebee; color: #c62828; }
    </style>
</head>
<body>
    <h1>LLM Test Results</h1>
    <p><strong>Run ID:</strong> "#);
        
        html.push_str(&summary.run_id);
        html.push_str(&format!(r#"</p>
    <p><strong>Date:</strong> {}</p>
    <p><strong>Total Tests:</strong> {}</p>
    <p><strong>Models Tested:</strong> {}</p>
    
    <h2>Model Comparison</h2>
    <table>
        <tr>
            <th>Model</th>
            <th>Success Rate</th>
            <th>Avg Latency (ms)</th>
            <th>Avg Edit Distance</th>
            <th>Avg Semantic Similarity</th>
            <th>Avg Grammar Score</th>
        </tr>
"#, summary.timestamp.format("%Y-%m-%d %H:%M:%S"), summary.test_count, summary.model_count));

        // Add model comparison rows
        for model in &summary.models {
            let success_rate = if model.test_count > 0 {
                (model.success_count as f64 / model.test_count as f64) * 100.0
            } else {
                0.0
            };
            
            html.push_str(&format!(r#"
        <tr>
            <td>{}</td>
            <td>{:.1}% ({}/{})</td>
            <td>{:.2}</td>
            <td>{:.2}</td>
            <td>{:.4}</td>
            <td>{:.4}</td>
        </tr>"#,
                model.model_name,
                success_rate, 
                model.success_count, 
                model.test_count,
                model.avg_latency_ms,
                model.avg_edit_distance,
                model.avg_semantic_similarity,
                model.avg_grammar_score
            ));
        }
        
        html.push_str(r#"
    </table>
    
    <h2>Detailed Test Results</h2>
"#);

        // Group results by test_id for comparison
        let mut tests_by_id: HashMap<String, Vec<&TestResult>> = HashMap::new();
        for result in results {
            tests_by_id.entry(result.test_id.clone())
                .or_default()
                .push(result);
        }
        
        // Add detailed test results
        for (test_id, test_results) in tests_by_id {
            if let Some(first_result) = test_results.first() {
                html.push_str(&format!(r#"
    <div class="test-container">
        <h3>Test ID: {}</h3>
        <p><strong>Input:</strong> {}</p>
        <p><strong>Expected Output:</strong> {}</p>
        
        <h4>Model Responses</h4>
        <table>
            <tr>
                <th>Model</th>
                <th>Response</th>
                <th>Latency (ms)</th>
                <th>Edit Distance</th>
                <th>Semantic Similarity</th>
                <th>Grammar Score</th>
            </tr>
"#,
                    test_id,
                    first_result.input,
                    first_result.expected.as_deref().unwrap_or("Not provided")
                ));
                
                // Add each model's result
                for result in test_results {
                    let is_error = result.model_output.starts_with("ERROR:");
                    let response_class = if is_error { " class=\"error-response\"" } else { "" };
                    
                    html.push_str(&format!(r#"
            <tr>
                <td>{}</td>
                <td{}>{}</td>
                <td>{}</td>
                <td>{}</td>
                <td>{:.4}</td>
                <td>{:.4}</td>
            </tr>"#,
                        result.model,
                        response_class,
                        result.model_output.replace('<', "&lt;").replace('>', "&gt;"),
                        result.metrics.latency_ms,
                        result.metrics.edit_distance.unwrap_or(0),
                        result.metrics.semantic_similarity.unwrap_or(0.0),
                        result.metrics.grammar_check_score.unwrap_or(0.0)
                    ));
                }
                
                html.push_str(r#"
        </table>
    </div>
"#);
            }
        }
        
        html.push_str(r#"
</body>
</html>"#);

        // Write HTML to file
        let file_path = results_dir.join("report.html");
        fs::write(&file_path, html)?;
        Ok(file_path)
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use crate::llm_test_data::{Metrics, TestResult};
        use chrono::Utc;
        use tempfile::TempDir;
        
        #[test]
        fn test_analyze_test_run() {
            // Create test data
            let results = vec![
                TestResult {
                    test_id: "test1".to_string(),
                    input: "Input 1".to_string(),
                    expected: Some("Expected 1".to_string()),
                    model_output: "Output 1".to_string(),
                    model: "model1".to_string(),
                    timestamp: Utc::now(),
                    metrics: Metrics {
                        latency_ms: 100,
                        edit_distance: Some(5),
                        semantic_similarity: Some(0.8),
                        grammar_check_score: Some(0.9),
                    },
                },
                TestResult {
                    test_id: "test2".to_string(),
                    input: "Input 2".to_string(),
                    expected: Some("Expected 2".to_string()),
                    model_output: "Output 2".to_string(),
                    model: "model1".to_string(),
                    timestamp: Utc::now(),
                    metrics: Metrics {
                        latency_ms: 200,
                        edit_distance: Some(10),
                        semantic_similarity: Some(0.7),
                        grammar_check_score: Some(0.8),
                    },
                },
                TestResult {
                    test_id: "test1".to_string(),
                    input: "Input 1".to_string(),
                    expected: Some("Expected 1".to_string()),
                    model_output: "Output 1b".to_string(),
                    model: "model2".to_string(),
                    timestamp: Utc::now(),
                    metrics: Metrics {
                        latency_ms: 150,
                        edit_distance: Some(3),
                        semantic_similarity: Some(0.9),
                        grammar_check_score: Some(0.95),
                    },
                },
            ];
            
            // Run analysis
            let summary = analyze_test_run(&results, "test_run_123");
            
            // Verify results
            assert_eq!(summary.run_id, "test_run_123");
            assert_eq!(summary.test_count, 3);
            assert_eq!(summary.model_count, 2);
            assert_eq!(summary.models.len(), 2);
            
            // Check first model
            let model1 = summary.models.iter().find(|m| m.model_name == "model1").unwrap();
            assert_eq!(model1.test_count, 2);
            assert_eq!(model1.success_count, 2);
            assert_eq!(model1.error_count, 0);
            assert_eq!(model1.avg_latency_ms, 150.0); // (100 + 200) / 2
            assert_eq!(model1.avg_edit_distance, 7.5); // (5 + 10) / 2
            assert!((model1.avg_semantic_similarity - 0.75).abs() < 0.001); // (0.8 + 0.7) / 2
            assert!((model1.avg_grammar_score - 0.85).abs() < 0.001); // (0.9 + 0.8) / 2
            
            // Check second model
            let model2 = summary.models.iter().find(|m| m.model_name == "model2").unwrap();
            assert_eq!(model2.test_count, 1);
            assert_eq!(model2.success_count, 1);
            assert_eq!(model2.error_count, 0);
            assert_eq!(model2.avg_latency_ms, 150.0);
            assert_eq!(model2.avg_edit_distance, 3.0);
            assert!((model2.avg_semantic_similarity - 0.9).abs() < 0.001);
            assert!((model2.avg_grammar_score - 0.95).abs() < 0.001);
        }
        
        #[test]
        fn test_save_analysis() {
            // Create temporary directory
            let temp_dir = TempDir::new().unwrap();
            
            // Create test data
            let summary = TestRunSummary {
                run_id: "test_run_123".to_string(),
                timestamp: Utc::now(),
                test_count: 3,
                model_count: 2,
                models: vec![
                    ModelComparison {
                        model_name: "model1".to_string(),
                        test_count: 2,
                        success_count: 2,
                        error_count: 0,
                        avg_latency_ms: 150.0,
                        avg_edit_distance: 7.5,
                        avg_semantic_similarity: 0.75,
                        avg_grammar_score: 0.85,
                    },
                    ModelComparison {
                        model_name: "model2".to_string(),
                        test_count: 1,
                        success_count: 1,
                        error_count: 0,
                        avg_latency_ms: 150.0,
                        avg_edit_distance: 3.0,
                        avg_semantic_similarity: 0.9,
                        avg_grammar_score: 0.95,
                    },
                ],
            };
            
            // Save analysis
            let file_path = save_analysis(&summary, temp_dir.path()).unwrap();
            
            // Verify file exists
            assert!(file_path.exists());
            
            // Read and parse the file
            let content = fs::read_to_string(file_path).unwrap();
            let parsed: serde_json::Value = serde_json::from_str(&content).unwrap();
            
            // Verify content
            assert_eq!(parsed["run_id"].as_str().unwrap(), "test_run_123");
            assert_eq!(parsed["test_count"].as_i64().unwrap(), 3);
            assert_eq!(parsed["model_count"].as_i64().unwrap(), 2);
            assert_eq!(parsed["models"].as_array().unwrap().len(), 2);
        }
    }
}

use llm_test_data::{TestResult, Metrics, save_test_result, load_test_config, export_to_csv, generate_test_run_id, calculate_edit_distance};
use llm_metrics::{calculate_semantic_similarity, calculate_grammar_score, TimingMetrics};

// Helper function to load test configs
fn load_llm_config(config_file_name: &str) -> Result<AppConfig, String> {
    let config_dir = PathBuf::from("tests/config_files");
    let config_file_path = config_dir.join(config_file_name);

    println!("Loading LLM config from: {:?}", config_file_path);

    let config_loader = config::Config::builder()
        .add_source(config::File::from(config_file_path).required(true))
        .build()
        .map_err(|e| format!("Config loading error: {}", e))?;

    config_loader.try_deserialize::<AppConfig>().map_err(|e| format!("Config deserialization error: {}", e))
}

// Only run these tests when explicitly requested, as they call external APIs
#[tokio::test]
#[ignore] // Skip by default, run with: cargo test --test llm_integration_tests -- --include-ignored
async fn test_llm_responses() {
    // Generate a unique run ID for this test execution
    let test_run_id = generate_test_run_id();
    println!("Starting LLM integration test run: {}", test_run_id);
    
    // Check for API key in environment
    let api_key = std::env::var("OPENAI_API_KEY").unwrap_or_else(|_| {
        println!("⚠️  OPENAI_API_KEY environment variable not set. OpenAI tests will be skipped.");
        String::new()
    });

    // Read enhanced test sentences with expected corrections
    let test_config = load_test_config(Path::new("tests/llm_test_sentences_with_expected.toml"))
        .expect("Failed to load test configuration");
    
    println!("Loaded {} test sentences with expected corrections", test_config.sentences.len());

    // Define LLM configurations to test - using Arc<AppConfig> directly
    let mut openai_configs: Vec<Arc<AppConfig>> = Vec::new();
    let mut ollama_configs: Vec<Arc<AppConfig>> = Vec::new();

    // Read all config files from the config_files directory
    let config_dir = PathBuf::from("tests/config_files");
    let mut entries = Vec::new();
    
    // With tokio::fs::read_dir, we need to iterate through the stream
    let mut dir = fs::read_dir(&config_dir).await.expect("Failed to read config directory");
    while let Some(entry) = dir.next_entry().await.expect("Failed to read directory entry") {
        entries.push(entry);
    }
    
    // Sort entries for consistent ordering
    entries.sort_by_key(|e| e.file_name());
    
    // Get all config file names
    let mut config_files = Vec::new();
    for entry in entries {
        let file_name = entry.file_name().to_string_lossy().to_string();
        if file_name.ends_with(".toml") {
            config_files.push(file_name);
        }
    }
    
    println!("Found {} config files: {:?}", config_files.len(), config_files);
    println!("Dynamically loading configs from the config_files directory...");

    // Only add OpenAI if we have an API key
    if !api_key.is_empty() {
        // Process OpenAI configs
        for file_name in &config_files {
            if file_name.contains("openai") {
                match load_llm_config(file_name) {
                    Ok(mut config) => {
                        // Set the API key from environment
                        config.openai_api_key = Some(api_key.clone());
                        println!("  Loaded OpenAI config: {}", file_name);
                        openai_configs.push(Arc::new(config));
                    }
                    Err(e) => println!("  Failed to load OpenAI config {}: {}", file_name, e),
                }
            }
        }
    }

    // Only add Ollama if it's available (localhost:11434)
    let ollama_check = reqwest::Client::new()
        .get("http://localhost:11434/api/version")
        .timeout(std::time::Duration::from_secs(1))
        .send()
        .await;

    if ollama_check.is_ok() {
        // Process Ollama configs
        for file_name in &config_files {
            if file_name.contains("ollama") {
                match load_llm_config(file_name) {
                    Ok(config) => {
                        println!("  Loaded Ollama config: {}", file_name);
                        ollama_configs.push(Arc::new(config));
                    }
                    Err(e) => println!("  Failed to load Ollama config {}: {}", file_name, e),
                }
            }
        }
    } else {
        println!("⚠️  Ollama server not detected at localhost:11434. Ollama tests will be skipped.");
    }

    // If no configs were loaded, skip the test
    if openai_configs.is_empty() && ollama_configs.is_empty() {
        println!("No LLM configurations available for testing. Skipping test.");
        return;
    }
    
    println!("Testing with {} OpenAI models and {} Ollama models", 
             openai_configs.len(), ollama_configs.len());

    // Create response and results directories
    let response_dir = PathBuf::from("tests/llm_responses");
    let results_dir = PathBuf::from("tests/results").join(&test_run_id);
    fs::create_dir_all(&response_dir).await.expect("Failed to create response directory");
    fs::create_dir_all(&results_dir).await.expect("Failed to create results directory");

    // Prepare to collect results for CSV export
    let mut all_results = Vec::new();

    // Configs are already grouped by provider type for sequential Ollama processing
    println!("\nLLM Models loaded for testing:");
    println!("- OpenAI models ({}): {}", openai_configs.len(), 
             openai_configs.iter().map(|c| c.model_name.as_str()).collect::<Vec<_>>().join(", "));
    println!("- Ollama models ({}): {}", ollama_configs.len(),
             ollama_configs.iter().map(|c| c.model_name.as_str()).collect::<Vec<_>>().join(", "));
    
    // Test each sentence with each model
    for test_sentence in &test_config.sentences {
        println!("--- Testing sentence ID: {} ---", test_sentence.id);
        println!("Text: '{}'", test_sentence.text);
        
        if let Some(expected) = &test_sentence.expected {
            println!("Expected: '{}'", expected);
        }

        // Process OpenAI models (can run in parallel if needed)
        for config in &openai_configs {
            let model_name = &config.model_name;
            println!("  Testing with OpenAI model: '{}'", model_name);

            // Set up timing metrics
            let mut timing = TimingMetrics::new();
            
            // Create request
            let client = Arc::new(Client::new());
            
            // Create a temporary cache for testing (disabled)
            let temp_dir = TempDir::new().expect("Failed to create temp dir for cache");
            let cache_path = temp_dir.path().join("test_cache.sled");
            let cache_config = CacheConfig {
                enabled: false, // Disable cache for integration tests
                ttl_days: 30,
                max_size_mb: 100,
            };
            let cache_manager = Arc::new(CacheManager::new(cache_path, cache_config).unwrap());
            
            let app_state = (config.clone(), client, cache_manager);
            let request = ProcessRequest {
                text: test_sentence.text.clone(),
            };

            // Process the request
            let result = process_text_handler(State(app_state), Json(request)).await;
            
            // Stop timing and get duration
            timing.stop();
            let latency_ms = timing.milliseconds();
            println!("  Response time: {}ms", latency_ms);

            // Process result and collect metrics
            match result {
                Ok(response) => {
                    println!("    Response from {}: {}", model_name, response.response);
                    
                    // Save response to a file (for backward compatibility)
                    let response_dir = format!(
                        "tests/llm_responses/{}",
                        model_name.replace("/", "_")
                    );
                    fs::create_dir_all(&response_dir)
                        .await
                        .expect("Failed to create response dir");
                    let sentence_file_name = format!(
                        "{}.txt",
                        test_sentence.id
                    );
                    let file_path = format!("{}/{}", response_dir, sentence_file_name);
                    fs::write(&file_path, &response.response)
                        .await
                        .expect("Failed to save response");
                    
                    // Calculate metrics if expected output is available
                    let mut metrics = Metrics {
                        latency_ms,
                        ..Default::default()
                    };
                    
                    if let Some(expected) = &test_sentence.expected {
                        metrics.edit_distance = Some(calculate_edit_distance(&response.response, expected));
                        metrics.semantic_similarity = Some(calculate_semantic_similarity(&response.response, expected));
                        metrics.grammar_check_score = Some(calculate_grammar_score(&response.response));
                        
                        println!("    Metrics:");
                        println!("      Edit Distance: {}", metrics.edit_distance.unwrap());
                        println!("      Semantic Similarity: {:.4}", metrics.semantic_similarity.unwrap());
                        println!("      Grammar Check Score: {:.4}", metrics.grammar_check_score.unwrap());
                    }
                    
                    // Create test result struct
                    let test_result = TestResult {
                        test_id: test_sentence.id.clone(),
                        input: test_sentence.text.clone(),
                        expected: test_sentence.expected.clone(),
                        model_output: response.response.clone(),
                        model: model_name.clone(),
                        timestamp: Utc::now(),
                        metrics,
                    };
                    
                    // Save detailed JSON result
                    let json_path = save_test_result(&test_result, &results_dir)
                        .expect("Failed to save test result");
                    println!("    Detailed result saved to: {:?}", json_path);
                    
                    // Add to overall results
                    all_results.push(test_result);
                }
                Err(e) => {
                    println!("    Error from {}: {:?}", model_name, e);
                    
                    // Save error message to file (backward compatibility)
                    let response_dir = format!(
                        "tests/llm_responses/{}",
                        model_name.replace("/", "_")
                    );
                    fs::create_dir_all(&response_dir)
                        .await
                        .expect("Failed to create response dir");
                    let sentence_file_name = format!(
                        "{}_ERROR.txt",
                        test_sentence.id
                    );
                    let file_path = format!("{}/{}", response_dir, sentence_file_name);
                    fs::write(&file_path, format!("ERROR: {:?}", e))
                        .await
                        .expect("Failed to save error");
                    
                    // Create error test result
                    let test_result = TestResult {
                        test_id: test_sentence.id.clone(),
                        input: test_sentence.text.clone(),
                        expected: test_sentence.expected.clone(),
                        model_output: format!("ERROR: {:?}", e),
                        model: model_name.clone(),
                        timestamp: Utc::now(),
                        metrics: Metrics {
                            latency_ms,
                            ..Default::default()
                        },
                    };
                    
                    // Save detailed JSON result
                    let json_path = save_test_result(&test_result, &results_dir)
                        .expect("Failed to save test result");
                    println!("    Detailed error result saved to: {:?}", json_path);
                    
                    // Add to overall results
                    all_results.push(test_result);
                }
            }
        }
        
        // Process Ollama models strictly one by one to avoid overloading
        for config in &ollama_configs {
            let model_name = &config.model_name;
            println!("  Testing with Ollama model: '{}'", model_name);

            // Set up timing metrics
            let mut timing = TimingMetrics::new();
            
            // Create request
            let client = Arc::new(Client::new());
            
            // Create a temporary cache for testing (disabled)
            let temp_dir = TempDir::new().expect("Failed to create temp dir for cache");
            let cache_path = temp_dir.path().join("test_cache.sled");
            let cache_config = CacheConfig {
                enabled: false, // Disable cache for integration tests
                ttl_days: 30,
                max_size_mb: 100,
            };
            let cache_manager = Arc::new(CacheManager::new(cache_path, cache_config).unwrap());
            
            let app_state = (config.clone(), client, cache_manager);
            let request = ProcessRequest {
                text: test_sentence.text.clone(),
            };

            // Process the request
            let result = process_text_handler(State(app_state), Json(request)).await;
            
            // Stop timing and get duration
            timing.stop();
            let latency_ms = timing.milliseconds();
            println!("  Response time: {}ms", latency_ms);

            // Process result and collect metrics
            match result {
                Ok(response) => {
                    println!("    Response from {}: {}", model_name, response.response);
                    
                    // Save response to a file (for backward compatibility)
                    let response_dir = format!(
                        "tests/llm_responses/{}",
                        model_name.replace("/", "_")
                    );
                    fs::create_dir_all(&response_dir)
                        .await
                        .expect("Failed to create response dir");
                    let sentence_file_name = format!(
                        "{}.txt",
                        test_sentence.id
                    );
                    let file_path = format!("{}/{}", response_dir, sentence_file_name);
                    fs::write(&file_path, &response.response)
                        .await
                        .expect("Failed to save response");
                    
                    // Calculate metrics if expected output is available
                    let mut metrics = Metrics {
                        latency_ms,
                        ..Default::default()
                    };
                    
                    if let Some(expected) = &test_sentence.expected {
                        metrics.edit_distance = Some(calculate_edit_distance(&response.response, expected));
                        metrics.semantic_similarity = Some(calculate_semantic_similarity(&response.response, expected));
                        metrics.grammar_check_score = Some(calculate_grammar_score(&response.response));
                        
                        println!("    Metrics:");
                        println!("      Edit Distance: {}", metrics.edit_distance.unwrap());
                        println!("      Semantic Similarity: {:.4}", metrics.semantic_similarity.unwrap());
                        println!("      Grammar Check Score: {:.4}", metrics.grammar_check_score.unwrap());
                    }
                    
                    // Create test result struct
                    let test_result = TestResult {
                        test_id: test_sentence.id.clone(),
                        input: test_sentence.text.clone(),
                        expected: test_sentence.expected.clone(),
                        model_output: response.response.clone(),
                        model: model_name.clone(),
                        timestamp: Utc::now(),
                        metrics,
                    };
                    
                    // Save detailed JSON result
                    let json_path = save_test_result(&test_result, &results_dir)
                        .expect("Failed to save test result");
                    println!("    Detailed result saved to: {:?}", json_path);
                    
                    // Add to overall results
                    all_results.push(test_result);
                }
                Err(e) => {
                    println!("    Error from {}: {:?}", model_name, e);
                    
                    // Save error message to file (backward compatibility)
                    let response_dir = format!(
                        "tests/llm_responses/{}",
                        model_name.replace("/", "_")
                    );
                    fs::create_dir_all(&response_dir)
                        .await
                        .expect("Failed to create response dir");
                    let sentence_file_name = format!(
                        "{}_ERROR.txt",
                        test_sentence.id
                    );
                    let file_path = format!("{}/{}", response_dir, sentence_file_name);
                    fs::write(&file_path, format!("ERROR: {:?}", e))
                        .await
                        .expect("Failed to save error");
                    
                    // Create error test result
                    let test_result = TestResult {
                        test_id: test_sentence.id.clone(),
                        input: test_sentence.text.clone(),
                        expected: test_sentence.expected.clone(),
                        model_output: format!("ERROR: {:?}", e),
                        model: model_name.clone(),
                        timestamp: Utc::now(),
                        metrics: Metrics {
                            latency_ms,
                            ..Default::default()
                        },
                    };
                    
                    // Save detailed JSON result
                    let json_path = save_test_result(&test_result, &results_dir)
                        .expect("Failed to save test result");
                    println!("    Detailed error result saved to: {:?}", json_path);
                    
                    // Add to overall results
                    all_results.push(test_result);
                }
            }
            
            // Stop the Ollama model after testing to free resources
            if model_name.contains("ollama") {
                let model_short_name = model_name.split('/').last().unwrap_or(model_name);
                println!("  Stopping Ollama model: {}", model_short_name);
                
                // Run the command to stop the model
                match std::process::Command::new("ollama")
                    .args(["stop", model_short_name])
                    .output() {
                        Ok(_) => println!("  Successfully stopped Ollama model: {}", model_short_name),
                        Err(e) => println!("  Failed to stop Ollama model: {}", e),
                    }
            }
        }
        
        println!("--- Sentence test complete ---\n");
    }
    
    // Export CSV results
    if !all_results.is_empty() {
        let csv_path = results_dir.join("results.csv");
        export_to_csv(&all_results, &csv_path).expect("Failed to export CSV results");
        println!("CSV export complete: {:?}", csv_path);
    }
    
    // Generate analysis
    use llm_analysis::{analyze_test_run, save_analysis, generate_html_report};
    let analysis = analyze_test_run(&all_results, &test_run_id);
    
    // Save analysis as JSON
    let json_path = save_analysis(&analysis, &results_dir).expect("Failed to save analysis");
    println!("Analysis saved to: {:?}", json_path);
    
    // Generate HTML report
    let html_path = generate_html_report(&analysis, &all_results, &results_dir).expect("Failed to generate HTML report");
    println!("HTML report generated: {:?}", html_path);

    // Summarize test run
    println!("\n=== LLM Integration Test Summary ===");
    println!("Test Run ID: {}", test_run_id);
    println!("Number of test cases: {}", test_config.sentences.len());
    println!("Models tested: {}", openai_configs.len() + ollama_configs.len());
    println!("Total tests run: {}", all_results.len());
    println!("Results directory: {:?}", results_dir);
    println!("CSV results: {:?}", results_dir.join("results.csv"));
    println!("Analysis: {:?}", json_path);
    println!("HTML Report: {:?}", html_path);
    println!("====================================\n");
    
    // Print model comparison
    println!("=== Model Comparison ===");
    for model in &analysis.models {
        let success_rate = if model.test_count > 0 {
            (model.success_count as f64 / model.test_count as f64) * 100.0
        } else {
            0.0
        };
        
        println!("- Model: {}", model.model_name);
        println!("  Success Rate: {:.1}% ({}/{})", 
            success_rate, model.success_count, model.test_count);
        println!("  Avg Latency: {:.2}ms", model.avg_latency_ms);
        println!("  Avg Edit Distance: {:.2}", model.avg_edit_distance);
        println!("  Avg Semantic Similarity: {:.4}", model.avg_semantic_similarity);
        println!("  Avg Grammar Score: {:.4}", model.avg_grammar_score);
        println!();
    }
    println!("=======================\n");
}