#!/usr/bin/env python3
"""
Simple Load Testing Script
Usage: python load_test.py
"""

import requests
import time
import threading
import os
import multiprocessing as mp
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
import statistics
import asyncio
import aiohttp

# Auto-detect optimal settings based on system
CPU_CORES = os.cpu_count()
OPTIMAL_THREADS = CPU_CORES * 4  # 4x cores is often optimal for I/O bound tasks

# Configuration
URL = "https://bb-basic-test-865238481351.europe-west1.run.app/"  # Change this to your target URL
NUM_REQUESTS = 100000  # Increased for high-performance systems
CONCURRENT_THREADS = min(OPTIMAL_THREADS, 120)  # Cap at 120 to avoid overwhelming
USE_ASYNC = True  # Use async for even better performance
TIMEOUT = 10  # seconds
RUN_DURATION = 0  # seconds; 0 means no time limit

print(f"System detected: {CPU_CORES} CPU cores")
print(f"Optimal threads calculated: {CONCURRENT_THREADS}")

# Global variables to store results (thread-safe)
results = []
errors = []
results_lock = threading.Lock()

async def make_async_request(session, semaphore):
    """Make an async HTTP request with semaphore for concurrency control"""
    async with semaphore:
        try:
            start_time = time.time()
            async with session.get(URL, timeout=aiohttp.ClientTimeout(total=TIMEOUT)) as response:
                await response.text()  # Read response body
                end_time = time.time()
                
                response_time = (end_time - start_time) * 1000  # Convert to milliseconds
                
                # Store result (thread-safe)
                result = {
                    'status_code': response.status,
                    'response_time': response_time,
                    'success': response.status == 200
                }
                
                with results_lock:
                    results.append(result)
                    if len(results) % 100 == 0:
                        print(f"Request {len(results)}: {response.status} - {response_time:.2f}ms")

        except Exception as e:
            with results_lock:
                errors.append(str(e))
                print(f"Error: {e}")

def make_request():
    """Make a single HTTP request and record the response time (sync version)"""
    try:
        start_time = time.time()
        response = requests.get(URL, timeout=TIMEOUT)
        end_time = time.time()
        
        response_time = (end_time - start_time) * 1000  # Convert to milliseconds
        
        # Store result (thread-safe)
        result = {
            'status_code': response.status_code,
            'response_time': response_time,
            'success': response.status_code == 200
        }
        
        with results_lock:
            results.append(result)
            print(f"Request {len(results)}: {response.status_code} - {response_time:.2f}ms")
        
    except Exception as e:
        with results_lock:
            errors.append(str(e))
            print(f"Error: {e}")

async def run_async_load_test():
    """Run the load test using async/await for maximum performance"""
    print(f"Starting ASYNC load test...")
    print(f"URL: {URL}")
    print(f"Total requests: {NUM_REQUESTS}")
    print(f"Concurrent connections: {CONCURRENT_THREADS}")
    print("-" * 50)
    
    start_time = time.time()
    
    # Create semaphore to limit concurrent connections
    semaphore = asyncio.Semaphore(CONCURRENT_THREADS)
    
    # Create aiohttp session
    connector = aiohttp.TCPConnector(limit=CONCURRENT_THREADS, limit_per_host=CONCURRENT_THREADS)
    async with aiohttp.ClientSession(connector=connector) as session:
        # Schedule tasks but stop scheduling when RUN_DURATION is exceeded (if set)
        tasks = []
        for i in range(NUM_REQUESTS):
            if RUN_DURATION and (time.time() - start_time) >= RUN_DURATION:
                print(f"Run duration {RUN_DURATION}s reached, stopping scheduling new requests (scheduled {len(tasks)} requests).")
                break
            # create task that will respect the semaphore
            tasks.append(asyncio.create_task(make_async_request(session, semaphore)))
            # yield occasionally to the event loop to avoid starvation
            if i % 100 == 0:
                await asyncio.sleep(0)

        # Run scheduled tasks (if any)
        if tasks:
            await asyncio.gather(*tasks)
        else:
            print("No tasks were scheduled due to run duration limit.")
    
    end_time = time.time()
    total_time = end_time - start_time
    
    # Calculate statistics
    print_results(total_time)

def run_load_test():
    """Run the load test with multiple threads (sync version)"""
    print(f"Starting THREADED load test...")
    print(f"URL: {URL}")
    print(f"Total requests: {NUM_REQUESTS}")
    print(f"Concurrent threads: {CONCURRENT_THREADS}")
    print("-" * 50)
    
    start_time = time.time()
    
    # Use ThreadPoolExecutor to manage concurrent requests
    with ThreadPoolExecutor(max_workers=CONCURRENT_THREADS) as executor:
        futures = []
        for i in range(NUM_REQUESTS):
            if RUN_DURATION and (time.time() - start_time) >= RUN_DURATION:
                print(f"Run duration {RUN_DURATION}s reached, stopping scheduling new requests (scheduled {len(futures)} requests).")
                break
            futures.append(executor.submit(make_request))

        # Wait for all scheduled requests to complete
        for future in futures:
            future.result()
    
    end_time = time.time()
    total_time = end_time - start_time
    
    # Calculate statistics
    print_results(total_time)

def print_results(total_time):
    """Print test results and statistics"""
    print("\n" + "=" * 50)
    print("LOAD TEST RESULTS")
    print("=" * 50)
    
    if not results:
        print("No successful requests!")
        return
    
    # Basic stats
    total_requests = len(results) + len(errors)
    successful_requests = len(results)
    failed_requests = len(errors)
    
    print(f"Total requests: {total_requests}")
    print(f"Successful requests: {successful_requests}")
    print(f"Failed requests: {failed_requests}")
    print(f"Success rate: {(successful_requests/total_requests)*100:.2f}%")
    print(f"Total time: {total_time:.2f} seconds")
    print(f"Requests per second: {total_requests/total_time:.2f}")
    print(f"CPU utilization: ~{(CONCURRENT_THREADS/CPU_CORES)*100:.1f}% of available cores")
    
    # Response time statistics
    response_times = [r['response_time'] for r in results]
    if response_times:
        print(f"\nResponse Time Statistics:")
        print(f"Average: {statistics.mean(response_times):.2f}ms")
        print(f"Median: {statistics.median(response_times):.2f}ms")
        print(f"Min: {min(response_times):.2f}ms")
        print(f"Max: {max(response_times):.2f}ms")
    
    # Status code breakdown
    status_codes = {}
    for result in results:
        code = result['status_code']
        status_codes[code] = status_codes.get(code, 0) + 1
    
    print(f"\nStatus Code Breakdown:")
    for code, count in status_codes.items():
        print(f"  {code}: {count} requests")
    
    # Show errors if any
    if errors:
        print(f"\nErrors:")
        for error in set(errors):  # Remove duplicates
            count = errors.count(error)
            print(f"  {error}: {count} times")

if __name__ == "__main__":
    print("High-Performance Load Testing Script")
    print(f"System: {CPU_CORES} CPU cores detected")
    print(f"Optimized for: {CONCURRENT_THREADS} concurrent connections")
    print("To change the URL, edit the URL variable in the script")
    print("Current URL:", URL)
    
    # Ask user if they want to proceed or change URL
    choice = input(f"\nPress Enter to test {URL} or type a new URL: ").strip()
    if choice:
        URL = choice
    
    # Ask user which mode to use
    print("\nChoose load test mode:")
    print("1. Async (fastest, recommended for high-core systems)")
    print("2. Threaded (traditional, good compatibility)")
    
    mode_choice = input("Enter choice (1 or 2, default=1): ").strip()
    
    # Ask user for optional run duration
    duration_choice = input("Optional: stop after N seconds (0 = no limit, default=0): ").strip()
    try:
        duration_val = float(duration_choice) if duration_choice else 0
        if duration_val < 0:
            duration_val = 0
    except Exception:
        duration_val = 0
    RUN_DURATION = duration_val
    
    try:
        if mode_choice == "2":
            USE_ASYNC = False
            run_load_test()
        else:
            USE_ASYNC = True
            asyncio.run(run_async_load_test())
    except KeyboardInterrupt:
        print("\nTest interrupted by user")
    except Exception as e:
        print(f"Test failed: {e}")
