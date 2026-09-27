require 'spaceship'
require 'base64'
require 'open3'
require 'cfpropertylist'

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch('FASTLANE_KEY_ID'),
  issuer_id: ENV.fetch('FASTLANE_ISSUER_ID'),
  key: ENV.fetch('FASTLANE_KEY')
)
# Only public provisioning metadata is printed, never the signing key or token.
profiles = Spaceship::ConnectAPI::Profile.all(filter: { profileType: 'IOS_APP_STORE' }, includes: 'bundleId')
profiles.select { |p| p.name.start_with?('match AppStore org.nightscout.FA4WP9H49T.trio') }.each do |profile|
  xml, _, status = Open3.capture3('openssl', 'cms', '-verify', '-inform', 'DER', '-noverify',
                                stdin_data: Base64.decode64(profile.profile_content))
  raise 'Cannot decode profile' unless status.success?
  plist = CFPropertyList.native_types(CFPropertyList::List.new(data: xml).value)
  entitlements = plist.fetch('Entitlements')
  puts "#{profile.name}: state=#{profile.profile_state}, groups=#{entitlements['com.apple.security.application-groups'].inspect}"
end

# Opt-in repair after the existing App Group is assigned in Apple Developer.
# Match will recreate this one profile during the next signed build.
# Distribution certificates and other apps' profiles are never changed.
if ENV['REFRESH_LIVE_ACTIVITY_PROFILE'] == 'true'
  candidates = profiles.select { |p| p.name == 'match AppStore org.nightscout.FA4WP9H49T.trio.LiveActivity' }
  raise 'Expected exactly one LiveActivity profile' unless candidates.length == 1
  candidates.first.delete!
  puts 'Removed only the Trio LiveActivity profile; match must regenerate it before signing.'
end
