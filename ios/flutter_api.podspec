Pod::Spec.new do |s|
  s.name             = 'flutter_api'
  s.version          = '0.0.1'
  s.summary          = 'Internal plugin with StoreKit intro-offer bridge'
  s.description      = 'Adds isEligibleForIntroOffer check'
  s.homepage         = 'https://github.com/netigenkluzowicz/Flutter_API.git'
  s.license          = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author           = { 'Netigen' => 'biuro@netigen.eu' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*'
  s.dependency       'Flutter'
  s.frameworks       = 'StoreKit'
  s.ios.deployment_target = '11.0'
end
