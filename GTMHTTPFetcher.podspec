Pod::Spec.new do |s|
  s.name        = 'GTMHTTPFetcher'
  s.version     = '1.1.0'
  s.authors     = 'Google Inc.'
  s.license     = { :type => 'Apache', :file => 'LICENSE' }
  s.homepage    = 'https://github.com/google/gtm-http-fetcher'
  s.source      = { :git => 'https://github.com/google/gtm-http-fetcher.git',
                    :tag => "v#{s.version}" }
  s.summary     = 'Google Toolbox for Mac - HTTP Fetcher'
  s.description = <<-DESC

  GTMHTTPFetcher makes it easy for Cocoa applications to
  perform http operations. The fetcher is implemented as a
  wrapper on NSURLConnection, so its behavior is asynchronous
  and uses operating-system settings on iOS and Mac OS X.
  DESC
  
  s.ios.deployment_target = '4.0'
  s.osx.deployment_target = '10.6'

  s.requires_arc = false
  
  s.subspec 'Fetcher' do |sp|
    sp.source_files = 'Source/GTMHTTPFetcher.{h,m}'
  end

  s.subspec 'Logging' do |sp|
    sp.source_files = 'Source/GTMHTTPFetcherLogging.{h,m}'
    sp.dependency 'GTMHTTPFetcher/Fetcher', "#{s.version}"
  end
  
  s.subspec 'LogViewController' do |sp|
    sp.platform = :ios
    sp.source_files = 'Source/GTMHTTPFetcherLogViewController.{h,m}'
    sp.dependency 'GTMHTTPFetcher/Logging', "#{s.version}"
  end
  
  s.subspec 'MIME' do |sp|
    sp.source_files =
      'Source/GTMMIMEDocument.{h,m}',
      'Source/GTMGatherInputStream.{h,m}'
    sp.dependency 'GTMHTTPFetcher/Fetcher', "#{s.version}"
  end
  
  s.subspec 'ResumableUpload' do |sp|
    sp.source_files = 'Source/GTMHTTPUploadFetcher.{h,m}'
    sp.dependency 'GTMHTTPFetcher/Fetcher', "#{s.version}"
    sp.dependency 'GTMHTTPFetcher/Service', "#{s.version}"
  end

  s.subspec 'Service' do |sp|
    sp.source_files =
      'Source/GTMHTTPFetcherService.{h,m}',
      'Source/GTMHTTPFetchHistory.{h,m}'
    sp.dependency 'GTMHTTPFetcher/Fetcher', "#{s.version}"
  end
end
