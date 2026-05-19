# macOS pod spec for aria2_native (FFI plugin).

Pod::Spec.new do |s|
  s.name             = 'aria2_native'
  s.version          = '0.1.0'
  s.summary          = 'libaria2 FFI bindings for aria2down.'
  s.description      = 'Dart FFI bindings to a thin C shim around libaria2.'
  s.homepage         = 'https://github.com/aria2/aria2'
  s.license          = { :file => '../LICENSE', :type => 'GPL-2.0-or-later' }
  s.author           = { 'aria2down' => 'noreply@iothub.cloud' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '11.0'
  s.swift_version = '5.0'

  prebuilt_root = '../prebuilt/macos/universal'
  libaria2      = "#{prebuilt_root}/libaria2.a"
  has_libaria2  = File.exist?(File.expand_path(libaria2, __dir__))

  if has_libaria2
    full_dir = File.expand_path(prebuilt_root, __dir__)
    deps     = Dir.glob("#{full_dir}/deps/*.a")
    s.xcconfig = {
      'GCC_PREPROCESSOR_DEFINITIONS' => 'ARIA2_FFI_WITH_LIBARIA2=1',
      'HEADER_SEARCH_PATHS'           => "#{full_dir}/include",
      'OTHER_LDFLAGS'                 => "#{full_dir}/libaria2.a " + deps.join(' '),
      'CLANG_CXX_LANGUAGE_STANDARD'   => 'gnu++14',
    }
  else
    s.xcconfig = {
      'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++14',
    }
  end

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
