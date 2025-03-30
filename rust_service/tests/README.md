# Writer AI Tests

This directory contains test files for the Writer AI Rust service, focusing on integration tests and LLM response quality evaluation.

## Test Structure

The tests are organized into the following components:

- **Unit Tests**: Located within each source file in `src/` under the `#[cfg(test)]` module
- **Integration Tests**: Located in this directory (`tests/`)
  - `llm_integration_tests.rs`: Tests for different LLM providers and configurations
  - `llm_test_sentences.toml`: Sample sentences for testing LLM responses
  - `config_files/`: Configuration files for different LLM setups

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
1. Read test sentences from `llm_test_sentences.toml`
2. Process each sentence through different LLM configurations
3. Save the responses to `tests/llm_responses/[model_name]/`

### Test Output

After running the LLM integration tests, you'll find the responses in the `tests/llm_responses/` directory, organized by model:

```
tests/llm_responses/
├── gpt-4o/
│   ├── sentence_1.txt
│   ├── sentence_2.txt
│   └── ...
└── llama3/
    ├── sentence_1.txt
    ├── sentence_2.txt
    └── ...
```

## Adding Test Sentences

To add more test sentences, edit `llm_test_sentences.toml`:

```toml
sentences = [
    "My English is no such god. Howe ar you?",
    "Weather here change alot. I not used it.",
    # Add your new test sentences here
]
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

2. Update the `llm_integration_tests.rs` file to include the new configuration.

## Analyzing Results

The integration tests require manual review to evaluate the quality of responses. When reviewing:

1. Compare responses across models to see which performs better
2. Look for improvements in grammar, clarity, and fluency
3. Check if the original meaning is preserved
4. Identify any hallucinations or incorrect changes

## Testing Tips

- Use a variety of sentence types with different grammatical issues
- Include some already-correct sentences to check if the LLM unnecessarily changes them
- For local models with Ollama, make sure the Ollama service is running before tests
- Keep in mind that API costs can add up quickly when running integration tests with many sentences