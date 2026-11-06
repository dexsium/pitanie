Pod::Spec.new do |s|
  s.name             = 'watch_ancs'
  s.version          = '0.0.1'
  s.summary          = 'Статус доступа часов к ANCS (только чтение).'
  s.homepage         = 'https://github.com/dexsium/pitanie'
  s.license          = { :type => 'AGPL-3.0' }
  s.author           = { 'pitanie' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'watch_ancs/Sources/watch_ancs/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'CoreBluetooth'
end
