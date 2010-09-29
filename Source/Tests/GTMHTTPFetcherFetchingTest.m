/* Copyright (c) 2009 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <SenTestingKit/SenTestingKit.h>

#import "GTMHTTPFetcherTestServer.h"
#import "GTMHTTPFetcher.h"
#import "GTMHTTPFetchHistory.h"
#import "GTMHTTPFetcherLogging.h"

@interface GTMHTTPFetcherFetchingTest : SenTestCase {

  // these ivars are checked after fetches, and are reset by resetFetchResponse
  NSData *fetchedData_;
  NSError *fetcherError_;
  int fetchedStatus_;
  NSURLResponse *fetchedResponse_;
  NSMutableURLRequest *fetchedRequest_;
  int retryCounter_;

  int fetchStartedNotificationCount_;
  int fetchStoppedNotificationCount_;
  int retryDelayStartedNotificationCount_;
  int retryDelayStoppedNotificationCount_;

  // setup/teardown ivars
  GTMHTTPFetchHistory *fetchHistory_;
  GTMHTTPFetcherTestServer *testServer_;
  BOOL isServerRunning_;
}

- (void)testFetch;
- (void)testWrongFetch;
- (void)testRetryFetches;

- (GTMHTTPFetcher *)doFetchWithURLString:(NSString *)urlString
                          cachingDatedData:(BOOL)doCaching;

- (GTMHTTPFetcher *)doFetchWithURLString:(NSString *)urlString
                          cachingDatedData:(BOOL)doCaching
                             retrySelector:(SEL)retrySel
                          maxRetryInterval:(NSTimeInterval)maxRetryInterval
                                credential:(NSURLCredential *)credential
                                  userData:(id)userData;

- (NSString *)localURLStringToTestFileName:(NSString *)name;
- (NSString *)localPathForFileName:(NSString *)name;
@end

@implementation GTMHTTPFetcherFetchingTest

static const NSTimeInterval kRunLoopInterval = 0.01;

//  The wrong-fetch test can take >10s to pass.
static const NSTimeInterval kGiveUpInterval = 30.0;

// file available in Tests folder
static NSString *const kValidFileName = @"gettysburgaddress.txt";

- (NSString *)docPathForName:(NSString *)fileName {
  NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
  STAssertNotNil(testBundle, nil);

  NSString *docPath = [testBundle pathForResource:fileName
                                           ofType:nil];
  STAssertNotNil(docPath, nil);

  return docPath;
}

- (NSString *)docRootPath {
  NSString *docRoot = [self docPathForName:kValidFileName];
  docRoot = [docRoot stringByDeletingLastPathComponent];
  return docRoot;
}

- (void)setUp {
  fetchHistory_ = [[GTMHTTPFetchHistory alloc] init];

  NSString *docRoot = [self docRootPath];

  testServer_ = [[GTMHTTPFetcherTestServer alloc] initWithDocRoot:docRoot];
  isServerRunning_ = (testServer_ != nil);

  STAssertTrue(isServerRunning_,
               @">>> http test server failed to launch; skipping"
               " fetcher tests\n");

  // install observers for fetcher notifications
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self selector:@selector(fetchStateChanged:) name:kGTMHTTPFetcherStartedNotification object:nil];
  [nc addObserver:self selector:@selector(fetchStateChanged:) name:kGTMHTTPFetcherStoppedNotification object:nil];
  [nc addObserver:self selector:@selector(retryDelayStateChanged:) name:kGTMHTTPFetcherRetryDelayStartedNotification object:nil];
  [nc addObserver:self selector:@selector(retryDelayStateChanged:) name:kGTMHTTPFetcherRetryDelayStoppedNotification object:nil];
}

- (void)resetFetchResponse {
  [fetchedData_ release];
  fetchedData_ = nil;

  [fetcherError_ release];
  fetcherError_ = nil;

  [fetchedRequest_ release];
  fetchedRequest_ = nil;

  [fetchedResponse_ release];
  fetchedResponse_ = nil;

  fetchedStatus_ = 0;

  retryCounter_ = 0;
}

- (void)tearDown {
  [testServer_ release];
  testServer_ = nil;

  isServerRunning_ = NO;

  [self resetFetchResponse];

  [fetchHistory_ release];
  fetchHistory_ = nil;
}

#pragma mark Notification callbacks

- (void)fetchStateChanged:(NSNotification *)note {
  if ([[note name] isEqual:kGTMHTTPFetcherStartedNotification]) {
    ++fetchStartedNotificationCount_;
  } else {
    ++fetchStoppedNotificationCount_;
  }

  STAssertTrue(fetchStartedNotificationCount_ <= fetchStartedNotificationCount_,
               @"fetch notification imbalance: starts=%d stops=%d",
               fetchStartedNotificationCount_,
               fetchStoppedNotificationCount_);
}

- (void)retryDelayStateChanged:(NSNotification *)note {
  if ([[note name] isEqual:kGTMHTTPFetcherRetryDelayStartedNotification]) {
    ++retryDelayStartedNotificationCount_;
  } else {
    ++retryDelayStoppedNotificationCount_;
  }

  STAssertTrue(retryDelayStoppedNotificationCount_ <= retryDelayStartedNotificationCount_,
               @"retry delay notification imbalance: starts=%d stops=%d",
               retryDelayStartedNotificationCount_,
               retryDelayStoppedNotificationCount_);
}

- (void)resetNotificationCounts {
  fetchStartedNotificationCount_ = 0;
  fetchStoppedNotificationCount_ = 0;
  retryDelayStartedNotificationCount_ = 0;
  retryDelayStoppedNotificationCount_ = 0;
}

#pragma mark Tests

- (void)testFetch {
  if (!isServerRunning_) return;

  [self resetNotificationCounts];
  [self resetFetchResponse];

  NSString *urlString = [self localURLStringToTestFileName:kValidFileName];
  [self doFetchWithURLString:urlString cachingDatedData:YES];

  STAssertNotNil(fetchedData_,
                 @"failed to fetch data, status:%d error:%@, URL:%@",
                 fetchedStatus_, fetcherError_, urlString);

  // we'll verify we fetched from the server the actual data on disk
  NSString *gettysburgPath = [testServer_ localPathForFile:kValidFileName];
  NSData *gettysburgAddress = [NSData dataWithContentsOfFile:gettysburgPath];
  STAssertEqualObjects(fetchedData_, gettysburgAddress,
                       @"Lincoln disappointed");

  STAssertNotNil(fetchedResponse_,
                 @"failed to get fetch response, status:%d error:%@",
                 fetchedStatus_, fetcherError_);
  STAssertNotNil(fetchedRequest_,
                 @"failed to get fetch request, URL %@", urlString);
  STAssertNil(fetcherError_, @"fetching data gave error: %@", fetcherError_);
  STAssertEquals(fetchedStatus_, 200,
                 @"unexpected status for URL %@", urlString);

  // no cookies should be sent with our first request
  NSDictionary *headers = [fetchedRequest_ allHTTPHeaderFields];
  NSString *cookiesSent = [headers objectForKey:@"Cookie"];
  STAssertNil(cookiesSent, @"Cookies sent unexpectedly: %@", cookiesSent);

  // cookies should have been set by the response; specifically, TestCookie
  // should be set to the name of the file requested
  NSDictionary *responseHeaders;

  responseHeaders = [(NSHTTPURLResponse *)fetchedResponse_ allHeaderFields];
  NSString *cookiesSetString = [responseHeaders objectForKey:@"Set-Cookie"];
  NSString *cookieExpected = [NSString stringWithFormat:@"TestCookie=%@",
    kValidFileName];
  STAssertEqualObjects(cookiesSetString, cookieExpected, @"Unexpected cookie");

  // make a copy of the fetched data to compare with our next fetch from the
  // cache
  NSData *originalFetchedData = [[fetchedData_ copy] autorelease];


  // Now fetch again so the "If-None-Match" header will be set (because
  // we're calling setFetchHistory: below) and caching ON, and verify that we
  // got a good data from the cache and a nil error, along with a
  // "Not Modified" status in the fetcher

  [self resetFetchResponse];

  [self doFetchWithURLString:urlString cachingDatedData:YES];

  STAssertEqualObjects(fetchedData_, originalFetchedData,
                       @"cache data mismatch");

  STAssertNotNil(fetchedData_,
                 @"failed to fetch data, status:%d error:%@, URL:%@",
                 fetchedStatus_, fetcherError_, urlString);
  STAssertNotNil(fetchedResponse_,
                 @"failed to get fetch response, status:%d error:%@",
                 fetchedStatus_, fetcherError_);
  STAssertNotNil(fetchedRequest_,
                 @"failed to get fetch request, URL %@",
                 urlString);
  STAssertNil(fetcherError_, @"fetching data gave error: %@", fetcherError_);

  STAssertEquals(fetchedStatus_, kGTMHTTPFetcherStatusNotModified, // 304
               @"fetch status unexpected for URL %@", urlString);

  // the TestCookie set previously should be sent with this request
  cookiesSent = [[fetchedRequest_ allHTTPHeaderFields] objectForKey:@"Cookie"];
  STAssertEqualObjects(cookiesSent, cookieExpected, @"Cookie not sent");


  // Now fetch twice without caching enabled, and verify that we got a
  // "Precondition failed" status, along with a non-nil but empty NSData (which
  // is normal for that status code) from the second fetch

  [self resetFetchResponse];

  [fetchHistory_ clearHistory];

  [self doFetchWithURLString:urlString cachingDatedData:NO];

  STAssertEqualObjects(fetchedData_, originalFetchedData,
                       @"cache data mismatch");
  STAssertNil(fetcherError_, @"unexpected error: %@", fetcherError_);

  [self resetFetchResponse];
  [self doFetchWithURLString:urlString cachingDatedData:NO];

  STAssertNotNil(fetchedData_, @"");
  STAssertEquals([fetchedData_ length], (NSUInteger) 0, @"unexpected data");
  STAssertEquals(fetchedStatus_, kGTMHTTPFetcherStatusNotModified,
         @"fetching data expected status 304, instead got %d", fetchedStatus_);
  STAssertNotNil(fetcherError_, @"missing 304 error");

  // check the notifications
  STAssertEquals(fetchStartedNotificationCount_, 4, @"fetches started");
  STAssertEquals(fetchStoppedNotificationCount_, 4, @"fetches stopped");
  STAssertEquals(retryDelayStartedNotificationCount_, 0, @"retries started");
  STAssertEquals(retryDelayStoppedNotificationCount_, 0, @"retries started");
}

- (void)testWrongFetch {

  if (!isServerRunning_) return;
  [self resetNotificationCounts];

  // fetch a live, invalid URL
  NSString *badURLString = @"http://localhost:86/";
  [self doFetchWithURLString:badURLString cachingDatedData:NO];

  if (fetchedData_) {
    NSString *str = [[[NSString alloc] initWithData:fetchedData_
                                           encoding:NSUTF8StringEncoding] autorelease];
    STAssertNil(fetchedData_, @"fetched unexpected data: %@", str);
  }

  STAssertNotNil(fetcherError_, @"failed to receive fetching error");
  STAssertEquals(fetchedStatus_, (NSInteger) 0,
                 @"unexpected status from no response");

  // fetch with a specific status code from our http server
  [self resetFetchResponse];

  NSString *invalidWebPageFile = [kValidFileName stringByAppendingString:@"?status=400"];
  NSString *statusUrlString = [self localURLStringToTestFileName:invalidWebPageFile];

  [self doFetchWithURLString:statusUrlString cachingDatedData:NO];

  STAssertNotNil(fetchedData_, @"fetch lacked data with error info");
  STAssertNotNil(fetcherError_, @"expected status error");
  STAssertEquals(fetchedStatus_, 400,
                 @"unexpected status, error=%@", fetcherError_);

  // check the notifications
  STAssertEquals(fetchStartedNotificationCount_, 2, @"fetches started");
  STAssertEquals(fetchStoppedNotificationCount_, 2, @"fetches stopped");
  STAssertEquals(retryDelayStartedNotificationCount_, 0, @"retries started");
  STAssertEquals(retryDelayStoppedNotificationCount_, 0, @"retries started");
}

- (void)testFetchToFileHandle {
  if (!isServerRunning_) return;

  [self resetFetchResponse];
  [self resetNotificationCounts];

  // create an empty file from which we can make an NSFileHandle
  NSString *path = [NSTemporaryDirectory() stringByAppendingFormat:@"fhTest_%u",
                    TickCount()];
  [[NSData data] writeToFile:path atomically:YES];

  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
  STAssertNotNil(fileHandle, @"missing filehandle for %@", path);

  // make the http request to our test server
  NSString *urlString = [self localURLStringToTestFileName:kValidFileName];
  NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                       cachePolicy:NSURLRequestReloadIgnoringCacheData
                                   timeoutInterval:kGiveUpInterval];
  GTMHTTPFetcher *fetcher = [GTMHTTPFetcher fetcherWithRequest:req];
  STAssertNotNil(fetcher, @"Failed to allocate fetcher");

  [fetcher setDownloadFileHandle:fileHandle];

  // received-data block
  //
  // the final received-data block invocation should show the length of the
  // file actually downloaded
  __block NSUInteger receivedDataLen = 0;
  [fetcher setReceivedDataBlock:^(NSData *dataReceivedSoFar) {
    // a nil data argument is expected when the downloaded data is written
    // to a file handle
    STAssertNil(dataReceivedSoFar, @"unexpected dataReceivedSoFar");

    receivedDataLen = [fileHandle offsetInFile];
  }];

  // fetch & completion block
  __block BOOL hasFinishedFetching = NO;
  [fetcher beginFetchWithCompletionHandler:^(NSData *data, NSError *error) {
    STAssertNil(data, @"unexpected data");
    STAssertNil(error, @"unexpected error");

    NSString *fetchedContents = [NSString stringWithContentsOfFile:path
                                                          encoding:NSUTF8StringEncoding
                                                             error:NULL];
    STAssertEquals(receivedDataLen, [fetchedContents length],
                   @"length issue");

    NSString *origPath = [self localPathForFileName:kValidFileName];
    NSString *origContents = [NSString stringWithContentsOfFile:origPath
                                                       encoding:NSUTF8StringEncoding
                                                          error:NULL];
    STAssertEqualObjects(fetchedContents, origContents, @"fetch to FH error");

    hasFinishedFetching = YES;
  }];

  // spin until the fetch completes
  NSDate* giveUpDate = [NSDate dateWithTimeIntervalSinceNow:kGiveUpInterval];
  while ((!hasFinishedFetching) && [giveUpDate timeIntervalSinceNow] > 0) {
    NSDate* loopIntervalDate = [NSDate dateWithTimeIntervalSinceNow:kRunLoopInterval];
    [[NSRunLoop currentRunLoop] runUntilDate:loopIntervalDate];
  }

  [[NSFileManager defaultManager] removeItemAtPath:path
                                             error:NULL];
}

- (void)testRetryFetches {

  if (!isServerRunning_) return;
  [self resetNotificationCounts];

  GTMHTTPFetcher *fetcher;

  NSString *invalidFile = [kValidFileName stringByAppendingString:@"?status=503"];
  NSString *urlString = [self localURLStringToTestFileName:invalidFile];

  SEL countRetriesSel = @selector(countRetriesfetcher:willRetry:forError:);
  SEL fixRequestSel = @selector(fixRequestFetcher:willRetry:forError:);

  //
  // test: retry until timeout, then expect failure with status message
  //

  NSNumber *lotsOfRetriesNumber = [NSNumber numberWithInt:1000];

  fetcher= [self doFetchWithURLString:urlString
                     cachingDatedData:NO
                        retrySelector:countRetriesSel
                     maxRetryInterval:5.0 // retry intervals of 1, 2, 4
                           credential:nil
                             userData:lotsOfRetriesNumber];

  STAssertNotNil(fetchedData_, @"error data is expected");
  STAssertEquals(fetchedStatus_, 503,
                 @"fetchedStatus_ should be 503, was %@", fetchedStatus_);
  STAssertEquals([fetcher retryCount], (unsigned) 3, @"retry count unexpected");

  //
  // test:  retry twice, then give up
  //
  [self resetFetchResponse];

  NSNumber *twoRetriesNumber = [NSNumber numberWithInt:2];

  fetcher= [self doFetchWithURLString:urlString
                     cachingDatedData:NO
                        retrySelector:countRetriesSel
                     maxRetryInterval:10.0 // retry intervals of 1, 2, 4, 8
                           credential:nil
                             userData:twoRetriesNumber];

  STAssertNotNil(fetchedData_, @"error data is expected");
  STAssertEquals(fetchedStatus_, 503,
                 @"fetchedStatus_ should be 503, was %@", fetchedStatus_);
  STAssertEquals([fetcher retryCount], (unsigned) 2, @"retry count unexpected");


  //
  // test:  retry, making the request succeed on the first retry
  //        by fixing the URL
  //
  [self resetFetchResponse];

  fetcher= [self doFetchWithURLString:urlString
                     cachingDatedData:NO
                        retrySelector:fixRequestSel
                     maxRetryInterval:30.0 // should only retry once due to selector
                           credential:nil
                             userData:lotsOfRetriesNumber];

  STAssertNotNil(fetchedData_, @"data is expected");
  STAssertEquals(fetchedStatus_, 200,
                 @"fetchedStatus_ should be 200, was %@", fetchedStatus_);
  STAssertEquals([fetcher retryCount], (unsigned) 1, @"retry count unexpected");

  // check the notifications
  STAssertEquals(fetchStartedNotificationCount_, 9, @"fetches started");
  STAssertEquals(fetchStoppedNotificationCount_, 9, @"fetches stopped");
  STAssertEquals(retryDelayStartedNotificationCount_, 6, @"retries started");
  STAssertEquals(retryDelayStoppedNotificationCount_, 6, @"retries started");
}

#pragma mark -

- (GTMHTTPFetcher *)doFetchWithURLString:(NSString *)urlString
                          cachingDatedData:(BOOL)doCaching {

  return [self doFetchWithURLString:(NSString *)urlString
                   cachingDatedData:doCaching
                      retrySelector:nil
                   maxRetryInterval:0
                         credential:nil
                           userData:nil];
}

- (GTMHTTPFetcher *)doFetchWithURLString:(NSString *)urlString
                        cachingDatedData:(BOOL)doCaching
                           retrySelector:(SEL)retrySel
                        maxRetryInterval:(NSTimeInterval)maxRetryInterval
                              credential:(NSURLCredential *)credential
                                userData:(id)userData {
  NSURL *url = [NSURL URLWithString:urlString];
  NSURLRequest *req = [NSURLRequest requestWithURL:url
                                       cachePolicy:NSURLRequestReloadIgnoringCacheData
                                   timeoutInterval:kGiveUpInterval];
  GTMHTTPFetcher *fetcher = [GTMHTTPFetcher fetcherWithRequest:req];

  STAssertNotNil(fetcher, @"Failed to allocate fetcher");

  // setting the fetch history will add the "If-modified-since" header
  // to repeat requests
  [fetchHistory_ setShouldCacheETaggedData:doCaching];
  [fetcher setFetchHistory:fetchHistory_];

  if (retrySel) {
    [fetcher setRetryEnabled:YES];
    [fetcher setRetrySelector:retrySel];
    [fetcher setMaxRetryInterval:maxRetryInterval];
    [fetcher setUserData:userData];

    // we force a minimum retry interval for unit testing; otherwise,
    // we'd have no idea how many retries will occur before the max
    // retry interval occurs, since the minimum would be random
    [fetcher setMinRetryInterval:1.0];
  }

  [fetcher setCredential:credential];

  BOOL isFetching = [fetcher beginFetchWithDelegate:self
                                  didFinishSelector:@selector(testFetcher:finishedWithData:error:)];
  STAssertTrue(isFetching, @"Begin fetch failed");

  if (isFetching) {
    // Give time for the fetch to happen, but give up if 10 seconds elapse with no response
    NSDate* giveUpDate = [NSDate dateWithTimeIntervalSinceNow:kGiveUpInterval];
    while ((!fetchedData_ && !fetcherError_) && [giveUpDate timeIntervalSinceNow] > 0) {
      NSDate* loopIntervalDate = [NSDate dateWithTimeIntervalSinceNow:kRunLoopInterval];
      [[NSRunLoop currentRunLoop] runUntilDate:loopIntervalDate];
    }  
  }

  return fetcher;
}

- (NSString *)localPathForFileName:(NSString *)name {
  NSString *docRoot = [self docRootPath];
  NSString *filePath = [docRoot stringByAppendingPathComponent:name];
  return filePath;
}

- (NSString *)localURLStringToTestFileName:(NSString *)name {

  // we need to create http URLs referring to the desired
  // resource to be found by the http server running locally

  // return a localhost:port URL for the test file
  NSString *urlString = [NSString stringWithFormat:@"http://localhost:%d/%@",
    [testServer_ port], name];

  // we exclude parameters
  NSRange range = [name rangeOfString:@"?"];
  if (range.location != NSNotFound) {
    name = [name substringToIndex:range.location];
  }

  // just for sanity, let's make sure we see the file locally, so
  // we can expect the Python http server to find it too
  NSString *filePath = [self localPathForFileName:name];

  BOOL doesExist = [[NSFileManager defaultManager] fileExistsAtPath:filePath];
  STAssertTrue(doesExist, @"Missing test file %@", filePath);

  return urlString;
}

- (void)testFetcher:(GTMHTTPFetcher *)fetcher
   finishedWithData:(NSData *)data
              error:(NSError *)error {
  fetchedData_ = [data copy];
  fetchedStatus_ = [fetcher statusCode];
  fetchedRequest_ = [[fetcher mutableRequest] retain];
  fetchedResponse_ = [[fetcher response] retain];
  fetcherError_ = [error retain];
}


// Selector for allowing up to N retries, where N is an NSNumber in the
// fetcher's userData
- (BOOL)countRetriesfetcher:(GTMHTTPFetcher *)fetcher
                  willRetry:(BOOL)suggestedWillRetry
                   forError:(NSError *)error {

  int count = [fetcher retryCount];
  int allowedRetryCount = [[fetcher userData] intValue];

  BOOL shouldRetry = (count < allowedRetryCount);

  STAssertEquals([fetcher nextRetryInterval], pow(2.0, [fetcher retryCount]),
                 @"unexpected next retry interval (expected %f, was %f)",
                 pow(2.0, [fetcher retryCount]),
                 [fetcher nextRetryInterval]);

  return shouldRetry;
}

// Selector for retrying and changing the request to one that will succeed
- (BOOL)fixRequestFetcher:(GTMHTTPFetcher *)fetcher
                willRetry:(BOOL)suggestedWillRetry
                 forError:(NSError *)error {

  STAssertEquals([fetcher nextRetryInterval], pow(2.0, [fetcher retryCount]),
                 @"unexpected next retry interval (expected %f, was %f)",
                 pow(2.0, [fetcher retryCount]),
                 [fetcher nextRetryInterval]);

  // fix it - change the request to a URL which does not have a status value
  NSString *urlString = [self localURLStringToTestFileName:kValidFileName];

  NSURL *url = [NSURL URLWithString:urlString];
  [[fetcher mutableRequest] setURL:url];

  return YES; // do the retry fetch; it should succeed now
}

@end
