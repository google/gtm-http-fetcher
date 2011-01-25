/* Copyright (c) 2010 Google Inc.
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

//
//  GTMHTTPFetcherTestServer.m
//

#import "GTMHTTPFetcherTestServer.h"

@interface GTMHTTPFetcherTestServer ()
- (NSString *)valueForParameter:(NSString *)paramName path:(NSString *)path;
@end

@implementation GTMHTTPFetcherTestServer

- (id)initWithDocRoot:(NSString *)docRoot {
  self = [super init];
  if (self) {
    docRoot_ = [docRoot copy];
    server_ = [[GTMHTTPServer alloc] initWithDelegate:self];
    NSError *error = nil;
    if ((docRoot == nil) || (![server_ start:&error])) {
      NSLog(@"Failed to start up the GTMHTTPFetcherTestServer "
            "(docRoot='%@', error=%@)", docRoot_, error);
      [self release];
      return nil;
    } else {
      NSLog(@"Started GTMHTTPFetcherTestServer on port %d (docRoot='%@')",
            [server_ port], docRoot_);
    }
  }
  return self;
}

- (void)stopServer {
  if (server_) {
    NSLog(@"Stopped GTMHTTPFetcherTestServer on port %d (docRoot='%@')",
          [server_ port], docRoot_);
    [server_ release];
    server_ = nil;

    [docRoot_ release];
    docRoot_ = nil;
  }
}

- (void)finalize {
  [self stopServer];
  [super finalize];
}

- (void)dealloc {
  [self stopServer];
  [super dealloc];
}

- (uint16_t)port {
  return [server_ port];
}

- (GTMHTTPResponseMessage *)httpServer:(GTMHTTPServer *)server
                         handleRequest:(GTMHTTPRequestMessage *)request {
  NSAssert(server == server_, @"how'd we get a different server?!");
  GTMHTTPResponseMessage *response;
  UInt32 resultStatus = 0;
  NSData *data = nil;
  NSMutableDictionary *responseHeaders = [NSMutableDictionary dictionary];

  NSString *etag = @"GoodETag";

  NSDictionary *requestHeaders = [request allHeaderFieldValues];
  NSString *ifMatch = [requestHeaders objectForKey:@"If-Match"];
  NSString *ifNoneMatch = [requestHeaders objectForKey:@"If-None-Match"];
  NSString *authorization = [requestHeaders objectForKey:@"Authorization"];
  NSString *path = [[request URL] absoluteString];

  if ([path hasSuffix:@".auth"]) {
    if (![authorization isEqualToString:@"GoogleLogin auth=GoodAuthToken"]) {
      GTMHTTPResponseMessage *response =
        [GTMHTTPResponseMessage emptyResponseWithCode:401];
      return response;
    } else {
      path = [path substringToIndex:[path length] - 5];
    }
  }

  NSString *method = [request method];

  // Code for future testing of the chunked-upload protocol
  //
  // This code is not yet tested
  NSString *host = [requestHeaders objectForKey:@"Host"];
  NSString *contentRange = [requestHeaders objectForKey:@"Content-Range"];

  // chunked (resumable) upload testing
  if ([[path pathExtension] isEqual:@"location"]) {

    // return a location header containing the request path with
    // the ".location" suffix changed to ".upload"
    NSString *pathWithoutLoc = [path stringByDeletingPathExtension];
    NSString *fullLocation = [NSString stringWithFormat:@"http://%@%@.upload",
                              host, pathWithoutLoc];

    [responseHeaders setValue:fullLocation forKey:@"Location"];
    resultStatus = 200;
    goto SendResponse;
  } else if ([[path pathExtension] isEqual:@"upload"]) {
    // chunked (resumable) upload testing

    // if the contentRange indicates this is a middle chunk,
    // return status 308 with a Range header; otherwise, strip
    // the ".upload" and continue to return the file
    //
    // contentRange is like
    //  Content-Range: bytes 0-49999/135681
    // or
    //  Content-Range: bytes * /135681
    NSScanner *crScanner = [NSScanner scannerWithString:contentRange];
    long long totalToUpload = 0;
    if ([crScanner scanString:@"bytes */" intoString:NULL]
        && [crScanner scanLongLong:&totalToUpload]) {
      // this is a query for where to resume; we'll arbitrarily resume at
      // half the total length of the upload
      long long resumeLocation = totalToUpload / 2;
      NSString *range = [NSString stringWithFormat:@"bytes=0-%lld",
                         resumeLocation];
      [responseHeaders setValue:range forKey:@"Range"];
      resultStatus = 308;
      goto SendResponse;
    }

    long long rangeLow = 0;
    long long rangeHigh = 0;
    if ([crScanner scanString:@"bytes " intoString:nil]
        && [crScanner scanLongLong:&rangeLow]
        && [crScanner scanString:@"-" intoString:NULL]
        && [crScanner scanLongLong:&rangeHigh]
        && [crScanner scanString:@"/" intoString:NULL]
        && [crScanner scanLongLong:&totalToUpload]) {
      // a chunk request
      if ((rangeHigh + 1) < totalToUpload) {
        // this is a middle chunk, so send a 308 status to ask for more chunks
        NSString *range = [NSString stringWithFormat:@"bytes=0-%lld",
                           rangeHigh];
        [responseHeaders setValue:range forKey:@"Range"];
        resultStatus = 308;
        goto SendResponse;
      } else {
        // this is the final chunk; remove the ".upload" at the end and
        // fall through to return the requested resource at the path
        path = [path stringByDeletingPathExtension];
      }
    }
  }

  NSString *statusStr = [self valueForParameter:@"status" path:path];
  if (statusStr) {
    // queries that have something like "?status=456" should fail with the
    // status code
    resultStatus = [statusStr intValue];

    NSString *template = @"{ \"error\" : { \"message\" : \"Server Status %u\","
                         @" \"code\" : %u } }";
    NSString *errorStr = [NSString stringWithFormat:template,
                          resultStatus, resultStatus];
    data = [errorStr dataUsingEncoding:NSUTF8StringEncoding];
  } else {
    if (ifMatch != nil && ![ifMatch isEqual:etag]) {
      // there is no match, hence this is an inconsistent PUT or DELETE
      resultStatus = 412; // precondition failed
    } else if (ifNoneMatch != nil && [ifNoneMatch isEqual:etag]) {
      // there is a match, hence this is a repetitive request
      if ([method isEqual:@"GET"] || [method isEqual:@"HEAD"]) {
        resultStatus = 304; // not modified
      } else {
        resultStatus = 412; // precondition failed
      }
    } else if ([method isEqualToString:@"DELETE"]) {
      // it's an object delete; return empty data
      resultStatus = 200;
    } else {
      // read and return the document from the path, or status 404 for not found
      NSString *docPath = [docRoot_ stringByAppendingPathComponent:path];
      data = [NSData dataWithContentsOfFile:docPath];
      if (data) {
        resultStatus = 200;
      } else {
        resultStatus = 404;
      }
    }
  }

  if ([method isEqual:@"GET"]) {
    [responseHeaders setValue:etag forKey:@"Etag"];
  }

  NSString *cookie = [NSString stringWithFormat:@"TestCookie=%@",
                      [path lastPathComponent]];
  [responseHeaders setValue:cookie forKey:@"Set-Cookie"];

  //
  // Finally, package up the response, and return it to the client
  //
SendResponse:
  response = [GTMHTTPResponseMessage responseWithBody:data
                                          contentType:@"application/json"
                                           statusCode:resultStatus];

  [response setHeaderValuesFromDictionary:responseHeaders];

  return response;
}

- (NSString *)valueForParameter:(NSString *)paramName path:(NSString *)path {
  // search the URL path for a parameter beginning with "paramName=" and
  // ending with & or the end-of-string
  NSString *result = nil;
  NSString *paramWithEquals = [paramName stringByAppendingString:@"="];
  NSRange paramNameRange = [path rangeOfString:paramWithEquals];
  if (paramNameRange.location != NSNotFound) {
    // we found the param name; find the end of the parameter
    NSCharacterSet *endSet = [NSCharacterSet characterSetWithCharactersInString:@"&\n"];
    NSUInteger startOfParam = paramNameRange.location + paramNameRange.length;
    NSRange endSearchRange = NSMakeRange(startOfParam,
                                         [path length] - startOfParam);
    NSRange endRange = [path rangeOfCharacterFromSet:endSet
                                             options:0
                                               range:endSearchRange];
    if (endRange.location == NSNotFound) {
      // param goes to end of string
      result = [path substringFromIndex:startOfParam];
    } else {
      // found and end marker
      NSUInteger paramLen = endRange.location - startOfParam;
      NSRange foundRange = NSMakeRange(startOfParam, paramLen);
      result = [path substringWithRange:foundRange];
    }
  } else {
    // param not found
  }
  return result;
}

// utilities for users
- (NSURL *)localURLForFile:(NSString *)name {
  // we need to create http URLs referring to the desired
  // resource to be found by the http server running locally

  // return a localhost:port URL for the test file
  NSString *urlString = [NSString stringWithFormat:@"http://localhost:%d/%@",
                         [self port], name];
  return [NSURL URLWithString:urlString];
}

- (NSString *)localPathForFile:(NSString *)name {
  // we exclude parameters
  NSRange range = [name rangeOfString:@"?"];
  if (range.location != NSNotFound) {
    name = [name substringToIndex:range.location];
  }
  NSString *filePath = [docRoot_ stringByAppendingPathComponent:name];
  return filePath;
}

@end
