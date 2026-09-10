Pod::Spec.new do |s|
  s.name             = 'pulser_sdk'
  s.version          = '1.0.0'
  s.summary          = 'Pulser SDK iOS plugin — APNs token registration and delivery tracking.'
  s.homepage         = 'https://github.com/levinkm/pulser-flutter-sdk'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Pulser' => 'support@pulser.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  s.dependency 'Flutter'
end
