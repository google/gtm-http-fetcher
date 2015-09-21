# Google Toolbox for Mac - HTTP Fetcher #

**Project site** <https://github.com/google/gtm-http-fetcher><br>
**Discussion group** <http://groups.google.com/group/google-toolbox-for-mac>

GTM HTTP Fetcher makes it easy for Cocoa applications to perform http
operations.  The fetcher is implemented as a wrapper on NSURLConnection, so its
behavior is asynchronous and uses operating-system settings on iOS and Mac OS X.

*NOTE:* Because NSURLConnection is deprecated as of iOS 9 and OS X 10.11, this
class has been superseded by
[GTMSessionFetcher](https://github.com/google/gtm-session-fetcher).

Features include:
- Simple to build; only one source/header file pair is required
- Simple to use: takes just two lines of code to fetch a request
- Callbacks are delegate/selector pairs or blocks
- Flexible cookie storage
- Caching of ETagged responses, reducing overhead of redundant fetches
- Automatic retry on errors, with exponential backoff
- Support for generating multipart MIME upload streams
- Easy, convenient logging of http requests and responses
- Fully independent of other projects

**To get started** with GTM HTTP Fetcher and the Objective-C Client Library,
read the [wiki](https://github.com/google/gtm-http-fetcher/wiki).

**If you have a problem**, please join the
[GTM discussion group](http://groups.google.com/group/google-toolbox-for-mac)
or submit an [issue](https://github.com/google/gtm-http-fetcher/issues).
