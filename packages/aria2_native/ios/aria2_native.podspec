# iOS pod spec for aria2_native (FFI plugin).
#
# The plugin ships a C ABI shim around libaria2. If a prebuilt
# libaria2.a + dependency archives exist under
# packages/aria2_native/prebuilt/ios/<arch>/, the shim is compiled with
# ARIA2_FFI_WITH_LIBARIA2=1; otherwise it builds as a stub.
#
# scripts/build_libaria2_ios.sh is responsible for populating prebuilt/.

Pod::Spec.new do |s|
  s.name             = 'aria2_native'
  s.version          = '0.1.0'
  s.summary          = 'libaria2 FFI bindings for aria2down.'
  s.description      = <<-DESC
    Dart FFI bindings to a thin C shim around libaria2 (third_party/aria2).
  DESC
  s.homepage         = 'https://github.com/aria2/aria2'
  s.license          = { :file => '../LICENSE', :type => 'GPL-2.0-or-later' }
  s.author           = { 'aria2down' => 'noreply@iothub.cloud' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'

  prebuilt_root  = '../prebuilt/ios'
  libaria2_arm64 = "#{prebuilt_root}/arm64/libaria2.a"
  has_libaria2   = File.exist?(File.expand_path(libaria2_arm64, __dir__))

  if has_libaria2
    arm64_dir = File.expand_path("#{prebuilt_root}/arm64", __dir__)
    sim_dir   = File.expand_path("#{prebuilt_root}/sim", __dir__)
    deps_arm  = Dir.glob("#{arm64_dir}/deps/*.a")
    deps_sim  = Dir.glob("#{sim_dir}/deps/*.a")
    s.xcconfig = {
      'GCC_PREPROCESSOR_DEFINITIONS' => 'ARIA2_FFI_WITH_LIBARIA2=1',
      'HEADER_SEARCH_PATHS'           => "#{arm64_dir}/include",
      'OTHER_LDFLAGS[sdk=iphoneos*]'        => "#{arm64_dir}/libaria2.a " + deps_arm.join(' '),
      'OTHER_LDFLAGS[sdk=iphonesimulator*]' => "#{sim_dir}/libaria2.a "   + deps_sim.join(' '),
      'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++14',
    }
  else
    s.xcconfig = {
      'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++14',
    }
  end

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
