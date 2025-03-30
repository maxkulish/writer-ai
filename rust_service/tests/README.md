# Writer AI Comprehensive Testing Framework

This directory contains the testing framework for the Writer AI Rust service, with a focus on comprehensive LLM response quality evaluation and performance metrics.

## Test Structure

The tests are organized into the following components:

- **Unit Tests**: Located within each source file in `src/` under the `#[cfg(test)]` module
- **Integration Tests**: Located in this directory (`tests/`)
  - `llm_integration_tests.rs`: Main test runner for LLM evaluation
  - `llm_test_data.rs`: Data structures and utilities for test management
  - `llm_metrics.rs`: Metric collection and calculation implementations
  - `llm_analysis.rs`: Analysis and visualization tools
  - `llm_test_sentences_with_expected.toml`: Test cases with expected corrections
  - `config_files/`: Configuration files for different LLM setups

## Key Features

The enhanced testing framework provides:

1. **Structured Data Collection**:
   - JSON-formatted test results with detailed metrics
   - Reference output collection for "gold standard" comparisons
   - Experiment tracking with unique test run IDs

2. **Automated Metrics**:
   - Latency and performance measurements
   - Edit distance calculation
   - Semantic similarity scoring
   - Grammar check validation

3. **Analysis and Reporting**:
   - CSV export for data analysis
   - JSON summaries with statistical analysis
   - HTML reports with interactive visualizations
   - Model comparison dashboards

## Running Tests

### Running Unit Tests

To run all unit tests:

```bash
cargo test
```

This will run all tests except those marked with `#[ignore]`.

### Running Integration Tests for LLMs

Integration tests for LLMs are marked with `#[ignore]` to avoid running them automatically during regular test runs, as they require external API access and may incur costs.

To run the LLM integration tests:

```bash
# Set your API key for tests that use OpenAI
export OPENAI_API_KEY='your-api-key-here'

# Run the integration tests
cargo test --test llm_integration_tests -- --include-ignored
```

The tests will:
1. Read test sentences with expected corrections from `llm_test_sentences_with_expected.toml`
2. Process each sentence through different LLM configurations
3. Calculate metrics by comparing against expected outputs
4. Generate detailed reports and analysis
5. Save all results to a uniquely identified test run directory

### Test Output

After running the enhanced LLM integration tests, you'll find:

```
tests/llm_responses/              # Individual responses (backward compatible)
├── gpt-4o/
│   ├── grammar-001.txt
│   ├── grammar-002.txt
│   └── ...
└── gemma3_12b/
    ├── grammar-001.txt
    ├── grammar-002.txt
    └── ...

tests/results/                    # Comprehensive results with metrics
├── run_20250330_123456_AbCdEf/   # Unique test run ID
│   ├── gpt-4o/                   # Results organized by model
│   │   ├── grammar-001.json
│   │   ├── grammar-002.json
│   │   └── ...
│   ├── gemma3_12b/
│   │   ├── grammar-001.json
│   │   ├── grammar-002.json
│   │   └── ...
│   ├── results.csv               # CSV export with all metrics
│   ├── analysis.json             # Statistical analysis
│   └── report.html               # Interactive HTML report
└── ...                           # Previous test runs
```

## Adding Test Sentences with Expected Corrections

To add more test cases, edit `llm_test_sentences_with_expected.toml`:

```toml
[[sentences]]
id = "grammar-003"
text = "I am interesting in learn more about rust programing."
expected = "I am interested in learning more about Rust programming."

[[sentences]]
id = "fluency-001"
text = "The cat sat on the mat and it was very fluffy."
expected = "The fluffy cat sat on the mat."
```

## Adding LLM Configurations

To test with additional LLM configurations:

1. Add a new config file to `tests/config_files/`:

   ```toml
   # tests/config_files/config_new_model.toml
   port = 8989
   llm_url = "https://api.example.com/v1/chat"
   model_name = "new-model"
   
   [llm_params]
   temperature = 0.5
   max_output_tokens = 1000
   ```

2. Update the `llm_integration_tests.rs` file to include the new configuration if needed.

## Metrics and Analysis

The framework collects and analyzes the following metrics:

### Quantitative Metrics
- **Latency**: Response time in milliseconds
- **Edit Distance**: Levenshtein distance between output and expected
- **Semantic Similarity**: Jaro-Winkler similarity score
- **Grammar Score**: Basic grammar correctness evaluation

### Analysis Capabilities
- **Model Comparison**: Side-by-side metrics for all tested models
- **Test Case Analysis**: Detailed breakdown of each test case
- **Success/Failure Rates**: Overall model reliability statistics
- **Performance Metrics**: Latency and throughput comparisons

## Reviewing Results

The HTML report provides a comprehensive view of test results, including:

1. **Overview Dashboard**: Summary statistics for the test run
2. **Model Comparison**: Comparative metrics across all tested models
3. **Detailed Test Results**: Side-by-side view of each model's response
4. **Metric Visualization**: Visual representations of performance metrics

For data analysis, use the CSV export with tools like Excel, Python/pandas, or R to perform custom analysis.

## Testing Tips

- Use a variety of sentence types with different grammatical issues
- Include edge cases to test model robustness
- For local models with Ollama, make sure the Ollama service is running before tests
- Keep in mind that API costs can add up quickly when running integration tests with many sentences
- Review the generated HTML report for in-depth analysis
- Compare metrics across test runs to track model improvements