# Simple Load Testing Script

A straightforward Python script to perform load testing on any URL.

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

## Usage

### Basic Usage
```bash
python load_test.py
```

The script will prompt you to either test the default URL or enter a new one.

### Configuration

Edit the script to change these settings:
- `URL`: Target URL to test (default: http://localhost:3000)
- `NUM_REQUESTS`: Total number of requests (default: 100)
- `CONCURRENT_THREADS`: Number of concurrent threads (default: 10)
- `TIMEOUT`: Request timeout in seconds (default: 10)

## Output

The script provides:
- Real-time progress of requests
- Success/failure rates
- Response time statistics (average, median, min, max)
- Requests per second
- Status code breakdown
- Error details

## Example Output

```
Starting load test...
URL: http://localhost:3000
Total requests: 100
Concurrent threads: 10
--------------------------------------------------
Request 1: 200 - 45.23ms
Request 2: 200 - 38.91ms
...

==================================================
LOAD TEST RESULTS
==================================================
Total requests: 100
Successful requests: 95
Failed requests: 5
Success rate: 95.00%
Total time: 12.34 seconds
Requests per second: 8.10

Response Time Statistics:
Average: 42.15ms
Median: 41.20ms
Min: 28.50ms
Max: 89.30ms

Status Code Breakdown:
  200: 95 requests

Errors:
  Connection timeout: 5 times
```

## Notes

- The script uses Python's `requests` library for HTTP requests
- Concurrent requests are handled using `ThreadPoolExecutor`
- All response times are measured in milliseconds
- Press Ctrl+C to stop the test early
