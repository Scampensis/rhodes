#------------------------------------------------------------------------
# (The MIT License)
# 
# Copyright (c) 2008-2011 Rhomobile, Inc.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# 
# http://rhomobile.com
#------------------------------------------------------------------------

require File.dirname(__FILE__) + '/androidcommon.rb'
require File.dirname(__FILE__) + '/android_tools.rb'
require 'pathname'

USE_OWN_STLPORT = false
#USE_TRACES = # see androidcommon.h

ANDROID_API_LEVEL_TO_MARKET_VERSION = {}
ANDROID_MARKET_VERSION_TO_API_LEVEL = {}
{2 => "1.1", 3 => "1.5", 4 => "1.6", 5 => "2.0", 6 => "2.0.1", 7 => "2.1", 8 => "2.2", 9 => "2.3.1", 10 => "2.3.3", 11 => "3.0", 12 => "3.1", 13 => "3.2"  }.each do |k,v|
  ANDROID_API_LEVEL_TO_MARKET_VERSION[k] = v
  ANDROID_MARKET_VERSION_TO_API_LEVEL[v] = k
end

def get_market_version(apilevel)
  ANDROID_API_LEVEL_TO_MARKET_VERSION[apilevel]
end

def get_api_level(version)
  ANDROID_MARKET_VERSION_TO_API_LEVEL[version]
end

JAVA_PACKAGE_NAME = 'com.rhomobile.rhodes'

# Here is place were android platform should be specified.
# For complete list of android API levels and its mapping to
# market names (such as "Android-1.5" etc) see output of
# command "android list targets"
ANDROID_SDK_LEVEL = 4

ANDROID_PERMISSIONS = {
  'audio' => ['RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS'],
  'camera' => 'CAMERA',
  'gps' => 'ACCESS_FINE_LOCATION',
  'network_state' => 'ACCESS_NETWORK_STATE',
  'phone' => ['CALL_PHONE', 'READ_PHONE_STATE'],
  'pim' => ['READ_CONTACTS', 'WRITE_CONTACTS', 'GET_ACCOUNTS'],
  'record_audio' => 'RECORD_AUDIO',
  'vibrate' => 'VIBRATE',
  'bluetooth' => ['BLUETOOTH_ADMIN', 'BLUETOOTH'],
  'calendar' => ['READ_CALENDAR', 'WRITE_CALENDAR'],
  'sdcard' => 'WRITE_EXTERNAL_STORAGE',
  'push' => proc do |manifest| add_push(manifest) end
}

ANDROID_CAPS_ALWAYS_ENABLED = ['network_state']

def add_push(manifest)
  element = REXML::Element.new('permission')
  element.add_attribute('android:name', "#{$app_package_name}.permission.C2D_MESSAGE")
  element.add_attribute('android:protectionLevel', 'signature')
  manifest.add element

  element = REXML::Element.new('uses-permission')
  element.add_attribute('android:name', "#{$app_package_name}.permission.C2D_MESSAGE")
  manifest.add element

  element = REXML::Element.new('uses-permission')
  element.add_attribute('android:name', "com.google.android.c2dm.permission.RECEIVE")
  manifest.add element

  receiver = REXML::Element.new('receiver')
  receiver.add_attribute('android:name', "#{JAVA_PACKAGE_NAME}.PushReceiver")
  receiver.add_attribute('android:permission', "com.google.android.c2dm.permission.SEND")

  action = REXML::Element.new('action')
  action.add_attribute('android:name', "com.google.android.c2dm.intent.RECEIVE")
  category = REXML::Element.new('category')
  category.add_attribute('android:name', $app_package_name)

  ie = REXML::Element.new('intent-filter')
  ie.add_element(action)
  ie.add_element(category)
  receiver.add_element(ie)

  action = REXML::Element.new('action')
  action.add_attribute('android:name', "com.google.android.c2dm.intent.REGISTRATION")
  category = REXML::Element.new('category')
  category.add_attribute('android:name', $app_package_name)
  
  ie = REXML::Element.new('intent-filter')
  ie.add_element(action)
  ie.add_element(category)
  receiver.add_element(ie)

  manifest.elements.each('application') do |app|
    app.add receiver
  end
end

def set_app_name_android(newname)
  puts "set_app_name"
  $stdout.flush

  rm_rf $appres
  cp_r $rhores, $appres

  iconappname = File.join($app_path, "icon", "icon.png")
  iconresname = File.join($appres, "drawable", "icon.png")
  rm_f iconresname
  cp iconappname, iconresname

  rhostrings = File.join($rhores, "values", "strings.xml")
  appstrings = File.join($appres, "values", "strings.xml")
  doc = REXML::Document.new(File.new(rhostrings))
  doc.elements["resources/string[@name='app_name']"].text = newname
  File.open(appstrings, "w") { |f| doc.write f }

  version = {'major' => 0, 'minor' => 0, 'patch' => 0}
  if $app_config["version"]
    if $app_config["version"] =~ /^(\d+)$/
      version["major"] = $1.to_i
    elsif $app_config["version"] =~ /^(\d+)\.(\d+)$/
      version["major"] = $1.to_i
      version["minor"] = $2.to_i
    elsif $app_config["version"] =~ /^(\d+)\.(\d+)\.(\d+)$/
      version["major"] = $1.to_i
      version["minor"] = $2.to_i
      version["patch"] = $3.to_i
    end
  end
  
  version = version["major"]*10000 + version["minor"]*100 + version["patch"]

  doc = REXML::Document.new(File.new($rhomanifest))
  doc.root.attributes['package'] = $app_package_name
  if version > 0
    doc.root.attributes['android:versionCode'] = version.to_s
    doc.root.attributes['android:versionName'] = $app_config["version"]
  end

  doc.elements.delete "manifest/application/uses-library[@android:name='com.google.android.maps']" unless $use_geomapping

  caps_proc = []
  # Default permissions. Need to be always enabled.
  caps = ['INTERNET', 'PERSISTENT_ACTIVITY', 'WAKE_LOCK']
  $app_config["capabilities"].each do |cap|
    cap = ANDROID_PERMISSIONS[cap]
    next if cap.nil?
    if cap.is_a? Proc
      caps_proc << cap
      next
    end
    cap = [cap] if cap.is_a? String
    cap = [] unless cap.is_a? Array
    caps += cap
  end
  caps.uniq!

  manifest = doc.elements["manifest"]

  manifest.elements.each('uses-sdk') { |e| manifest.delete e }
  
  element = REXML::Element.new('uses-sdk')
  element.add_attribute('android:minSdkVersion', $min_sdk_level.to_s)
  manifest.add element

  # Remove category LAUNCHER from all activities if hidden_app is set
  hidden_app = get_boolean($app_config['hidden_app'])
  if hidden_app
    manifest.elements.each('application') do |app|
      app.elements.each('activity') do |activity|
        activity.elements.each('intent-filter') do |intf|
          intf.elements.each('category') do |c|
            name = c.attribute('name', 'android')
            next if name.nil?
            intf.delete(c) if name.to_s == 'android.intent.category.LAUNCHER'
          end
        end
      end
    end
  end

  # Clear C2DM stuff
  doc.elements.delete "manifest/application/receiver[@android:name='#{JAVA_PACKAGE_NAME}.PushReceiver']"
  manifest.elements.each('permission') do |e|
    name = e.attribute('name', 'android')
    next if name.nil?
    manifest.delete(e) if name.to_s =~ /\.C2D_MESSAGE$/
  end

  app = doc.elements["manifest/application"]

  app.elements.each("activity") do |a|
    a.elements.each("intent-filter") do |filter|
      filter.elements.each("action") do |act|
        act_name = act.attribute("name", "android")
        next if act_name.nil?
        if act_name.to_s =~ /\.VIEW$/
          default_filter = false
          browsable_filter = false
          filter.elements.each("category") do |c|
            cat_name = c.attribute("name", "android")
            next if cat_name.nil?
            default_filter = true if cat_name.to_s =~ /\.DEFAULT$/
            browsable_filter = true if cat_name.to_s =~ /\.BROWSABLE$/
          end
          if default_filter and browsable_filter
            filter.elements.each("data") do |d|
              filter.delete d
            end
            uri_params = {"android:scheme" => $uri_scheme, "android:host" => $uri_host}
            uri_params["android:pathPrefix"] = $uri_path_prefix unless $uri_path_prefix.nil?
            filter.add_element "data", uri_params
          end
        end
      end
    end
  end

  provider = app.add_element(
    "provider",
    { "android:name" => "#{JAVA_PACKAGE_NAME}.LocalFileProvider",
      "android:authorities" => $app_package_name,
      "android:grantUriPermissions" => "false" } )

  provider.add_element "grant-uri-permission", { "android:pathPrefix" => "/rhodes/apps/" }

  manifest.elements.each('uses-permission') { |e| manifest.delete e }

  caps.sort.each do |cap|
    element = REXML::Element.new('uses-permission')
    element.add_attribute('android:name', "android.permission.#{cap}")
    manifest.add element
  end

  caps_proc.each do |p|
    p.call manifest
  end

  puts 'save updated application manifest'
  app_f = File.open($appmanifest, "w")
  doc.write app_f, 2
  app_f.close

  #File.open($appmanifest, "w") { |f| doc.write f, 2 }

  buf = File.new($rho_android_r,"r").read.gsub(/^\s*import com\.rhomobile\..*\.R;\s*$/,"\nimport #{$app_package_name}.R;\n")
  File.open($app_android_r,"w") { |f| f.write(buf) }
end

def generate_rjava
  Rake::Task["build:android:rjava"].execute
end

def get_boolean(arg)
  arg == 'true' or arg == 'yes' or arg == 'enabled' or arg == 'enable' or arg == '1'
end

namespace "config" do
  task :set_android_platform do
    $current_platform = "android"
  end

  task :android => [:set_android_platform, "config:common"] do

    $ext_android_rhodes_activity_listener = []
    $ext_android_manifest_changes= []
    $ext_android_resources_addons = []
    $ext_android_additional_sources_list = []

    $gapikey = $app_config["android"]["apikey"] unless $app_config["android"].nil?
    $gapikey = $config["android"]["apikey"] if $gapikey.nil? and not $config["android"].nil?
    $gapikey = '' unless $gapikey.is_a? String
    $gapikey = nil if $gapikey.empty?

    $use_geomapping = $app_config["android"]["mapping"] unless $app_config["android"].nil?
    $use_geomapping = $config["android"]["mapping"] if $use_geomapping.nil? and not $config["android"].nil?
    $use_geomapping = 'false' if $use_geomapping.nil?
    $use_geomapping = get_boolean($use_geomapping.to_s)

    $use_google_addon_api = false
    $use_google_addon_api = true if $use_geomapping

    #Additionally $use_google_addon_api set to true if PUSH capability is enabled

    puts "Use Google addon API: #{$use_google_addon_api}" if USE_TRACES

    $emuversion = $app_config["android"]["version"] unless $app_config["android"].nil?
    $emuversion = $config["android"]["version"] if $emuversion.nil? and !$config["android"].nil?

    $uri_scheme = $app_config["android"]["URIScheme"] unless $app_config["android"].nil?
    $uri_scheme = "http" if $uri_scheme.nil?

    $uri_host = $app_config["android"]["URIHost"] unless $app_config["android"].nil?

    $min_sdk_level = $app_config["android"]["minSDK"] unless $app_config["android"].nil?
    $min_sdk_level = $config["android"]["minSDK"] if $min_sdk_level.nil? and not $config["android"].nil?
    $min_sdk_level = $min_sdk_level.to_i unless $min_sdk_level.nil?
    $min_sdk_level = ANDROID_SDK_LEVEL if $min_sdk_level.nil?


    # Here is switch between release/debug configuration used for
    # building native libraries
    if $app_config["debug"].nil?
      $build_release = true
    else
      $build_release = !$app_config["debug"].to_i
    end

    $androidsdkpath = $config["env"]["paths"]["android"]
    unless File.exists? $androidsdkpath
      puts "Missing or invalid 'android' section in rhobuild.yml: '#{$androidsdkpath}'"
      exit 1
    end

    $androidndkpath = $config["env"]["paths"]["android-ndk"]
    unless File.exists? $androidndkpath
      puts "Missing or invalid 'android-ndk' section in rhobuild.yml: '#{$androidndkpath}'"
      exit 1
    end

    errfmt = "WARNING!!! Path to Android %s contain spaces! It will not work because of the Google toolchain restrictions. Move it to another location and reconfigure rhodes."
    #if $androidsdkpath =~ /\s/
    #  puts(errfmt % "SDK")
    #  exit 1
    #end
    if $androidndkpath =~ /\s/
      puts(errfmt % "NDK")
      exit 1
    end

    $java = $config["env"]["paths"]["java"]
    $androidpath = Jake.get_absolute $config["build"]["androidpath"]
    $bindir = File.join($app_path, "bin")
    $rhobindir = File.join($androidpath, "bin")
    $builddir = File.join($androidpath, "build")
    $shareddir = File.join($androidpath, "..", "shared")
    $srcdir = File.join($bindir, "RhoBundle")
    $targetdir = File.join($bindir, "target")
    $excludelib = ['**/builtinME.rb','**/ServeME.rb','**/dateME.rb','**/rationalME.rb']
    $tmpdir = File.join($bindir, "tmp")
    $resourcedir = File.join($tmpdir, "resource")
    $libs = File.join($androidpath, "Rhodes", "libs")
    $appname = $app_config["name"]
    $appname = "Rhodes" if $appname.nil?
    $vendor = $app_config["vendor"]
    $vendor = "rhomobile" if $vendor.nil?
    $vendor = $vendor.gsub(/^[^A-Za-z]/, '_').gsub(/[^A-Za-z0-9]/, '_').gsub(/_+/, '_').downcase
    $app_package_name = $app_config["android"] ? $app_config["android"]["package_name"] : nil
    $app_package_name = "com.#{$vendor}." + $appname.downcase.gsub(/[^A-Za-z_0-9]/, '') unless $app_package_name
    $app_package_name.gsub!(/\.[\d]/, "._")

    if $uri_host.nil?
      $uri_host = "rhomobile.com"
      $uri_path_prefix = "/#{$app_package_name}"
    end

    $rhomanifest = File.join $androidpath, "Rhodes", "AndroidManifest.xml"
    $appmanifest = File.join $tmpdir, "AndroidManifest.xml"

    $rhores = File.join $androidpath, "Rhodes", "res"
    $appres = File.join $tmpdir, "res"

    $appincdir = File.join $tmpdir, "include"

    $rho_android_r = File.join $androidpath, "Rhodes", "src", "com", "rhomobile", "rhodes", "AndroidR.java"
    $app_android_r = File.join $tmpdir, "AndroidR.java"
    $app_rjava_dir = File.join $tmpdir
    $app_native_libs_java = File.join $tmpdir, "NativeLibraries.java"
    $app_capabilities_java = File.join $tmpdir, "Capabilities.java"
    $app_push_java = File.join $tmpdir, "Push.java"

    if RUBY_PLATFORM =~ /(win|w)32$/
      $emulator = #"cmd /c " + 
        File.join( $androidsdkpath, "tools", "emulator.exe" )
      $bat_ext = ".bat"
      $exe_ext = ".exe"
      $path_separator = ";"

      # Add PATH to cygwin1.dll
      ENV['CYGWIN'] = 'nodosfilewarning'
      if $path_cygwin_modified.nil?
        ENV['PATH'] = Jake.get_absolute("res/build-tools") + ";" + ENV['PATH']
        path_cygwin_modified = true
      end
    else
      #XXX make these absolute
      $emulator = File.join( $androidsdkpath, "tools", "emulator" )
      $bat_ext = ""
      $exe_ext = ""
      $path_separator = ":"
      # TODO: add ruby executable for Linux
    end

    puts "+++ Looking for platform..." if USE_TRACES
    napilevel = $min_sdk_level
    
    android_api_levels = Array.new
    
    Dir.glob(File.join($androidsdkpath, "platforms", "*")).each do |platform|
      props = File.join(platform, "source.properties")
      unless File.file? props
        puts "+++ WARNING! No source.properties found in #{platform}"
        next
      end

      apilevel = -1
      marketversion = nil
      File.open(props, "r") do |f|
        while line = f.gets
          apilevel = $1.to_i if line =~ /^\s*AndroidVersion\.ApiLevel\s*=\s*([0-9]+)\s*$/
          marketversion = $1 if line =~ /^\s*Platform\.Version\s*=\s*([^\s]*)\s*$/
        end
      end

      puts "+++ API LEVEL of #{platform}: #{apilevel}" if USE_TRACES
      android_api_levels.push apilevel

      if apilevel >= napilevel
        napilevel = apilevel
        $androidplatform = File.basename(platform)
        $found_api_level = apilevel
      end
    end

    android_api_levels.sort!

    $emuversion = get_market_version($min_sdk_level) if $emuversion.nil?
    requested_api_level = get_api_level($emuversion)

    if USE_TRACES
      puts "Found API levels:"
      android_api_levels.each do |level|
        puts level
      end
      puts "Requested version: #{$emuversion}"
      puts "Corresponding API level #{requested_api_level}"
    end

    if requested_api_level.nil?
      puts "ERROR!!! Wrong Android API version: #{$emuversion}"
      exit 1
    end

    is_api_level_installed = false
    android_api_levels.each do |level|
      if level == requested_api_level
        is_api_level_installed = true
        break
      end
    end

    if !is_api_level_installed
      puts "ERROR!!! API version is not found in installed Android SDK: #{$emuversion}"
      exit 1
    end

    if $androidplatform.nil?
      ajar = File.join($androidsdkpath, 'platforms', 'android-' + $min_sdk_level.to_s, 'android.jar')
      if USE_TRACES
        puts "Using target path: "+ ajar
      end
      $androidplatform = 'android-' + $min_sdk_level.to_s if File.file?(ajar)
    end

    if $androidplatform.nil?
      puts "+++ No required platform (API level >= #{$min_sdk_level}) found, can't proceed"
      puts "+++ Looks like you have no installed required Android platform package."
      puts "+++ To solve that, please strictly follow instructions from http://wiki.rhomobile.com/index.php/BuildingRhodes#Prerequisites_5"
      exit 1
    else
      puts "+++ Platform found: #{$androidplatform}" if USE_TRACES
    end
    $stdout.flush
    
    $dx = File.join( $androidsdkpath, "platforms", $androidplatform, "tools", "dx" + $bat_ext )
    $dx = File.join( $androidsdkpath, "platform-tools", "dx" + $bat_ext ) unless File.exists? $dx
    $aapt = File.join( $androidsdkpath, "platforms", $androidplatform, "tools", "aapt" + $exe_ext )
    $aapt = File.join( $androidsdkpath, "platform-tools", "aapt" + $exe_ext ) unless File.exists? $aapt
    $apkbuilder = File.join( $androidsdkpath, "tools", "apkbuilder" + $bat_ext )
    $androidbin = File.join( $androidsdkpath, "tools", "android" + $bat_ext )
    $adb = File.join( $androidsdkpath, "tools", "adb" + $exe_ext )
    $adb = File.join( $androidsdkpath, "platform-tools", "adb" + $exe_ext ) unless File.exists? $adb
    $zipalign = File.join( $androidsdkpath, "tools", "zipalign" + $exe_ext )
    $androidjar = File.join($androidsdkpath, "platforms", $androidplatform, "android.jar")
    $dxjar = File.join( $androidsdkpath, "platforms", $androidplatform, "tools", "lib", "dx.jar")
    $dxjar = File.join( $androidsdkpath, "platform-tools", "lib", "dx.jar") unless File.exists? $dxjar

    $keytool = File.join( $java, "keytool" + $exe_ext )
    $jarsigner = File.join( $java, "jarsigner" + $exe_ext )
    $jarbin = File.join( $java, "jar" + $exe_ext )

    $keystore = nil
    $keystore = $app_config["android"]["production"]["certificate"] if !$app_config["android"].nil? and !$app_config["android"]["production"].nil?
    $keystore = $config["android"]["production"]["certificate"] if $keystore.nil? and !$config["android"].nil? and !$config["android"]["production"].nil?
    $keystore = File.expand_path(File.join(ENV['HOME'], ".rhomobile", "keystore")) if $keystore.nil?

    $storepass = nil
    $storepass = $app_config["android"]["production"]["password"] if !$app_config["android"].nil? and !$app_config["android"]["production"].nil?
    $storepass = $config["android"]["production"]["password"] if $storepass.nil? and !$config["android"].nil? and !$config["android"]["production"].nil?
    $storepass = "81719ef3a881469d96debda3112854eb" if $storepass.nil?
    $keypass = $storepass

    $storealias = nil
    $storealias = $app_config["android"]["production"]["alias"] if !$app_config["android"].nil? and !$app_config["android"]["production"].nil?
    $storealias = $config["android"]["production"]["alias"] if $storealias.nil? and !$config["android"].nil? and !$config["android"]["production"].nil?
    $storealias = "rhomobile.keystore" if $storealias.nil?

    $app_config["capabilities"] = [] if $app_config["capabilities"].nil?
    $app_config["capabilities"] = [] unless $app_config["capabilities"].is_a? Array
    if $app_config["android"] and $app_config["android"]["capabilities"]
      $app_config["capabilities"] += $app_config["android"]["capabilities"]
      $app_config["android"]["capabilities"] = nil
    end
    $app_config["capabilities"] += ANDROID_CAPS_ALWAYS_ENABLED
    $app_config["capabilities"].map! { |cap| cap.is_a?(String) ? cap : nil }.delete_if { |cap| cap.nil? }
    $use_google_addon_api = true unless $app_config["capabilities"].index("push").nil?
 
    $applog_path = nil
    $applog_file = $app_config["applog"]

    if !$applog_file.nil?
      $applog_path = File.join( $app_path, $applog_file )
    end 

    # Detect android targets
    if $androidtargets.nil?
      $androidtargets = {}
      id = nil

      `"#{$androidbin}" list targets`.split(/\n/).each do |line|
        line.chomp!

        if line =~ /^id:\s+([0-9]+)/
          id = $1
        end

        if $use_google_addon_api
          if line =~ /:Google APIs:([0-9]+)/
            apilevel = $1
            $androidtargets[apilevel.to_i] = id.to_i
          end
        else
          if line =~ /^\s+API\s+level:\s+([0-9]+)$/ and not id.nil?
            apilevel = $1
            $androidtargets[apilevel.to_i] = id.to_i
          end
        end
      end
    end

    # Detect Google API add-on path
    if $use_google_addon_api
      puts "+++ Looking for Google APIs add-on..." if USE_TRACES
      puts "Previously found API level: #{$found_api_level}" if USE_TRACES
      napilevel = $min_sdk_level
      Dir.glob(File.join($androidsdkpath, 'add-ons', '*')).each do |dir|

        props = File.join(dir, 'manifest.ini')
        if !File.file? props
          puts "+++ WARNING: no manifest.ini found in #{dir}"
          next
        end

        apilevel = -1
        File.open(props, 'r') do |f|
          while line = f.gets
            next unless line =~ /^api=([0-9]+)$/
            apilevel = $1.to_i
            break
          end
        end

        puts "+++ API LEVEL of #{dir}: #{apilevel}" if USE_TRACES

        if apilevel >= napilevel
          
          sgapijar = File.join(dir, 'libs', 'maps.jar')
          if File.exists? sgapijar
            napilevel = apilevel
            $gapijar = sgapijar
            $found_api_level = apilevel
          end
        end
      end
      if $gapijar.nil?
        raise "+++ No Google APIs add-on found (which is required because appropriate capabilities enabled in build.yml)"
      else
        puts "+++ Google APIs add-on found: #{$gapijar}" if USE_TRACES
      end
    end

    $emuversion = $emuversion.to_s
    $avdname = "rhoAndroid" + $emuversion.gsub(/[^0-9]/, "")
    $avdname += "ext" if $use_google_addon_api
    $avdtarget = $androidtargets[get_api_level($emuversion)]

    $appavdname = $app_config["android"]["emulator"] if $app_config["android"] != nil && $app_config["android"].length > 0
    $appavdname = $config["android"]["emulator"] if $appavdname.nil? and !$config["android"].nil? and $config["android"].length > 0

    setup_ndk($androidndkpath, $found_api_level)
    
    $std_includes = File.join $androidndkpath, "sources", "cxx-stl", "stlport", "stlport"
    unless File.directory? $std_includes
      $stlport_includes = File.join $shareddir, "stlport", "stlport"
      USE_OWN_STLPORT = true
    end

    $native_libs = ["sqlite", "curl", "stlport", "ruby", "json", "rhocommon", "rhodb", "rholog", "rhosync", "rhomain"]

    if $build_release
      $confdir = "release"
    else
      $confdir = "debug"
    end
    $objdir = {}
    $libname = {}
    $native_libs.each do |x|
      $objdir[x] = File.join($rhobindir, $confdir, $ndkabi, $ndkgccver, "lib" + x)
      $libname[x] = File.join($rhobindir, $confdir, $ndkabi, $ndkgccver, "lib" + x + ".a")
    end

    $extensionsdir = $bindir + "/libs/" + $confdir + "/" + $ndkabi + "/" + $ndkgccver + "/extensions"

    #$app_config["extensions"] = [] if $app_config["extensions"].nil?
    #$app_config["extensions"] = [] unless $app_config["extensions"].is_a? Array
    #if $app_config["android"] and $app_config["android"]["extensions"]
    #  $app_config["extensions"] += $app_config["android"]["extensions"]
    #  $app_config["android"]["extensions"] = nil
    #end

    $push_sender = nil
    $push_sender = $config["android"]["push"]["sender"] if !$config["android"].nil? and !$config["android"]["push"].nil?
    $push_sender = $app_config["android"]["push"]["sender"] if !$app_config["android"].nil? and !$app_config["android"]["push"].nil?
    $push_sender = "support@rhomobile.com" if $push_sender.nil?

    $push_notifications = nil
    $push_notifications = $app_config["android"]["push"]["notifications"] if !$app_config["android"].nil? and !$app_config["android"]["push"].nil?
    $push_notifications = "none" if $push_notifications.nil?
    $push_notifications = $push_notifications

    

    mkdir_p $bindir if not File.exists? $bindir
    mkdir_p $rhobindir if not File.exists? $rhobindir
    mkdir_p $targetdir if not File.exists? $targetdir
    mkdir_p $srcdir if not File.exists? $srcdir
    mkdir_p $libs if not File.exists? $libs

  end
end


namespace "build" do
  namespace "android" do
 #   desc "Generate R.java file"
    task :rjava => "config:android" do

      manifest = $appmanifest
      resource = $appres
      assets = Jake.get_absolute(File.join($androidpath, "Rhodes", "assets"))
      nativelibs = Jake.get_absolute(File.join($androidpath, "Rhodes", "libs"))
      #rjava = Jake.get_absolute(File.join($androidpath, "Rhodes", "gen", "com", "rhomobile", "rhodes"))

      args = ["package", "-f", "-M", manifest, "-S", resource, "-A", assets, "-I", $androidjar, "-J", $app_rjava_dir]
      puts Jake.run($aapt, args)

      unless $?.success?
        puts "Error in AAPT"
        exit 1
      end

    end
#    desc "Build RhoBundle for android"
    task :rhobundle => ["config:android","build:bundle:noxruby",:extensions] do
#      Rake::Task["build:bundle:noxruby"].execute

      assets = File.join(Jake.get_absolute($androidpath), "Rhodes", "assets")
      rm_rf assets
      mkdir_p assets
      hash = nil
      ["apps", "db", "lib"].each do |d|
        cp_r File.join($srcdir, d), assets, :preserve => true
        # Calculate hash of directories
        hash = get_dir_hash(File.join(assets, d), hash)
      end
      File.open(File.join(assets, "hash"), "w") { |f| f.write(hash.hexdigest) }

      File.open(File.join(assets, "name"), "w") { |f| f.write($appname) }
      
      psize = assets.size + 1

      File.open(File.join(assets, 'rho.dat'), 'w') do |dat|
        Dir.glob(File.join(assets, '**/*')).sort.each do |f|
          relpath = f[psize..-1]

          if File.directory?(f)
            type = 'dir'
          elsif File.file?(f)
            type = 'file'
          else
            next
          end
          size = File.stat(f).size
          tm = File.stat(f).mtime.to_i

          dat.puts "#{relpath}\t#{type}\t#{size.to_s}\t#{tm.to_s}"
        end
      end
    end

    task :extensions => :genconfig do

      ENV['RHO_PLATFORM'] = 'android'
      ENV["ANDROID_NDK"] = $androidndkpath
      ENV["ANDROID_API_LEVEL"] = $found_api_level.to_s
      ENV["TARGET_TEMP_DIR"] = $extensionsdir
      ENV["RHO_ROOT"] = $startdir
      ENV["BUILD_DIR"] ||= $startdir + "/platform/android/build"
      ENV["RHO_INC"] = $appincdir
      ENV["RHO_ANDROID_TMP_DIR"] = $tmpdir

      ext_build_files = File.join($extensionsdir, "ext_build.files")
      if File.exist? ext_build_files
           rm ext_build_files
      end

      mkdir_p $extensionsdir unless File.directory? $extensionsdir

      $app_config["extensions"].each do |ext|
        $app_config["extpaths"].each do |p|
          extpath = File.join(p, ext, 'ext')

          extyml = File.join(p, ext,"ext.yml")
          if File.file? extyml
            extconf = Jake.config(File.open(extyml))

            android_listener = extconf["android_rhodes_activity_listener"]
            $ext_android_rhodes_activity_listener << android_listener unless android_listener.nil?

            android_manifest_changes = extconf["android_manifest_changes"]
            if android_manifest_changes != nil
              android_manifest_changes = File.join(p, ext, android_manifest_changes)
              $ext_android_manifest_changes << android_manifest_changes
            end

            android_resources_addons = extconf["android_resources_addons"]
            if android_resources_addons != nil
              android_resources_addons = File.join(p, ext, android_resources_addons)
              $ext_android_resources_addons << android_resources_addons
            end

            android_additional_sources_list = extconf["android_additional_sources_list"]
            if android_additional_sources_list != nil
              android_additional_sources_list = File.join(p, ext, android_additional_sources_list)

              File.open(android_additional_sources_list, "r") do |f|
                  while line = f.gets
                    $ext_android_additional_sources_list << File.join(p, ext, line)
                  end
              end

            end
          end

          if RUBY_PLATFORM =~ /(win|w)32$/
            next unless File.exists? File.join(extpath, 'build.bat')
          else
            next unless File.executable? File.join(extpath, 'build')
          end

          ENV['TEMP_FILES_DIR'] = File.join(ENV["TARGET_TEMP_DIR"], ext)

          if RUBY_PLATFORM =~ /(win|w)32$/
            puts Jake.run('build.bat', [], extpath)
          else
            puts Jake.run('./build', [], extpath)
          end
          exit 1 unless $?.success?
        end
      end

    end

    task :libsqlite => "config:android" do
      srcdir = File.join($shareddir, "sqlite")
      objdir = $objdir["sqlite"]
      libname = $libname["sqlite"]

      cc_build 'libsqlite', objdir, ["-I#{srcdir}", "-I#{$shareddir}"] or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libcurl => "config:android" do
      # Steps to get curl_config.h from fresh libcurl sources:
      #export PATH=<ndkroot>/build/prebuilt/linux-x86/arm-eabi-4.2.1/bin:$PATH
      #export CC=arm-eabi-gcc
      #export CPP=arm-eabi-cpp
      #export CFLAGS="--sysroot <ndkroot>/build/platforms/android-3/arch-arm -fPIC -mandroid -DANDROID -DOS_ANDROID"
      #export CPPFLAGS="--sysroot <ndkroot>/build/platforms/android-3/arch-arm -fPIC -mandroid -DANDROID -DOS_ANDROID"
      #./configure --without-ssl --without-ca-bundle --without-ca-path --without-libssh2 --without-libidn --disable-ldap --disable-ldaps --host=arm-eabi

      srcdir = File.join $shareddir, "curl", "lib"
      objdir = $objdir["curl"]
      libname = $libname["curl"]

      args = []
      args << "-DHAVE_CONFIG_H"
      args << "-I#{srcdir}/../include"
      args << "-I#{srcdir}"
      args << "-I#{$shareddir}"      

      cc_build 'libcurl', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libruby => "config:android" do
      srcdir = File.join $shareddir, "ruby"
      objdir = $objdir["ruby"]
      libname = $libname["ruby"]
      args = []
      args << "-I#{srcdir}/include"
      args << "-I#{srcdir}/linux"
      args << "-I#{srcdir}/generated"
      args << "-I#{srcdir}"
      args << "-I#{srcdir}/.."
      args << "-I#{srcdir}/../sqlite"
      args << "-I#{$std_includes}" unless $std_includes.nil?
      args << "-D__NEW__" if USE_OWN_STLPORT
      args << "-I#{$stlport_includes}" if USE_OWN_STLPORT

      cc_build 'libruby', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libjson => "config:android" do
      srcdir = File.join $shareddir, "json"
      objdir = $objdir["json"]
      libname = $libname["json"]
      args = []
      args << "-I#{srcdir}"
      args << "-I#{srcdir}/.."
      args << "-I#{$std_includes}" unless $std_includes.nil?
      args << "-D__NEW__" if USE_OWN_STLPORT
      args << "-I#{$stlport_includes}" if USE_OWN_STLPORT

      cc_build 'libjson', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libstlport => "config:android" do
      if USE_OWN_STLPORT
        objdir = $objdir["stlport"]
        libname = $libname["stlport"]

        args = []
        args << "-I#{$stlport_includes}"
        args << "-DTARGET_OS=android"
        args << "-DOSNAME=android"
        args << "-DCOMPILER_NAME=gcc"
        args << "-DBUILD_OSNAME=android"
        args << "-D_REENTRANT"
        args << "-D__NEW__"
        args << "-ffunction-sections"
        args << "-fdata-sections"
        args << "-fno-rtti"
        args << "-fno-exceptions"

        cc_build 'libstlport', objdir, args or exit 1
        cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
      end
    end

    task :librholog => "config:android" do
      srcdir = File.join $shareddir, "logging"
      objdir = $objdir["rholog"]
      libname = $libname["rholog"]
      args = []
      args << "-I#{srcdir}/.."
      args << "-I#{$std_includes}" unless $std_includes.nil?
      args << "-D__NEW__" if USE_OWN_STLPORT
      args << "-I#{$stlport_includes}" if USE_OWN_STLPORT

      cc_build 'librholog', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :librhomain => "config:android" do
      srcdir = $shareddir
      objdir = $objdir["rhomain"]
      libname = $libname["rhomain"]
      args = []
      args << "-I#{srcdir}"
      args << "-I#{$std_includes}" unless $std_includes.nil?
      args << "-D__NEW__" if USE_OWN_STLPORT
      args << "-I#{$stlport_includes}" if USE_OWN_STLPORT

      cc_build 'librhomain', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :librhocommon => "config:android" do
      objdir = $objdir["rhocommon"]
      libname = $libname["rhocommon"]
      args = []
      args << "-I#{$shareddir}"
      args << "-I#{$shareddir}/curl/include"
      args << "-I#{$shareddir}/ruby/include"
      args << "-I#{$shareddir}/ruby/linux"
      args << "-I#{$std_includes}" unless $std_includes.nil?
      args << "-D__NEW__" if USE_OWN_STLPORT
      args << "-I#{$stlport_includes}" if USE_OWN_STLPORT

      cc_build 'librhocommon', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :librhodb => "config:android" do
      srcdir = File.join $shareddir, "db"
      objdir = $objdir["rhodb"]
      libname = $libname["rhodb"]
      args = []
      args << "-I#{srcdir}"
      args << "-I#{srcdir}/.."
      args << "-I#{srcdir}/../sqlite"
      args << "-I#{$std_includes}" unless $std_includes.nil?
      args << "-D__NEW__" if USE_OWN_STLPORT
      args << "-I#{$stlport_includes}" if USE_OWN_STLPORT

      cc_build 'librhodb', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :librhosync => "config:android" do
      srcdir = File.join $shareddir, "sync"
      objdir = $objdir["rhosync"]
      libname = $libname["rhosync"]
      args = []
      args << "-I#{srcdir}"
      args << "-I#{srcdir}/.."
      args << "-I#{srcdir}/../sqlite"
      args << "-I#{$std_includes}" unless $std_includes.nil?
      args << "-D__NEW__" if USE_OWN_STLPORT
      args << "-I#{$stlport_includes}" if USE_OWN_STLPORT

      cc_build 'librhosync', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libs => [:libsqlite, :libcurl, :libruby, :libjson, :libstlport, :librhodb, :librhocommon, :librhomain, :librhosync, :librholog]

    task :genconfig => "config:android" do
      mkdir_p $appincdir unless File.directory? $appincdir

      # Generate genconfig.h
      genconfig_h = File.join($appincdir, 'genconfig.h')

      gapi_already_enabled = false
      caps_already_enabled = {}
      #ANDROID_PERMISSIONS.keys.each do |k|
      #  caps_already_enabled[k] = false
      #end
      if File.file? genconfig_h
        File.open(genconfig_h, 'r') do |f|
          while line = f.gets
            if line =~ /^\s*#\s*define\s+RHO_GOOGLE_API_KEY\s+"[^"]*"\s*$/
              gapi_already_enabled = true
            else
              ANDROID_PERMISSIONS.keys.each do |k|
                if line =~ /^\s*#\s*define\s+RHO_CAP_#{k.upcase}_ENABLED\s+(.*)\s*$/
                  value = $1.strip
                  if value == 'true'
                    caps_already_enabled[k] = true
                  elsif value == 'false'
                    caps_already_enabled[k] = false
                  else
                    raise "Unknown value for the RHO_CAP_#{k.upcase}_ENABLED: #{value}"
                  end
                end
              end
            end
          end
        end
      end

      regenerate = false
      regenerate = true unless File.file? genconfig_h
      regenerate = $use_geomapping != gapi_already_enabled unless regenerate

      caps_enabled = {}
      ANDROID_PERMISSIONS.keys.each do |k|
        caps_enabled[k] = $app_config["capabilities"].index(k) != nil
        regenerate = true if caps_already_enabled[k].nil? or caps_enabled[k] != caps_already_enabled[k]
      end

      if regenerate
        puts "Need to regenerate genconfig.h"
        $stdout.flush
        File.open(genconfig_h, 'w') do |f|
          f.puts "#ifndef RHO_GENCONFIG_H_411BFA4742CF4F2AAA3F6B411ED7514F"
          f.puts "#define RHO_GENCONFIG_H_411BFA4742CF4F2AAA3F6B411ED7514F"
          f.puts ""
          f.puts "#define RHO_GOOGLE_API_KEY \"#{$gapikey}\"" if $use_geomapping and !$gapikey.nil?
          caps_enabled.each do |k,v|
            f.puts "#define RHO_CAP_#{k.upcase}_ENABLED #{v ? "true" : "false"}"
          end
          f.puts ""
          f.puts "#endif /* RHO_GENCONFIG_H_411BFA4742CF4F2AAA3F6B411ED7514F */"
        end
      else
        puts "No need to regenerate genconfig.h"
        $stdout.flush
      end

      # Generate rhocaps.inc
      rhocaps_inc = File.join($appincdir, 'rhocaps.inc')
      caps_already_defined = []
      if File.exists? rhocaps_inc
        File.open(rhocaps_inc, 'r') do |f|
          while line = f.gets
            next unless line =~ /^\s*RHO_DEFINE_CAP\s*\(\s*([A-Z_]*)\s*\)\s*\s*$/
            caps_already_defined << $1.downcase
          end
        end
      end

      if caps_already_defined.sort.uniq != ANDROID_PERMISSIONS.keys.sort.uniq
        puts "Need to regenerate rhocaps.inc"
        $stdout.flush
        File.open(rhocaps_inc, 'w') do |f|
          ANDROID_PERMISSIONS.keys.sort.each do |k|
            f.puts "RHO_DEFINE_CAP(#{k.upcase})"
          end
        end
      else
        puts "No need to regenerate rhocaps.inc"
        $stdout.flush
      end

      # Generate Capabilities.java
      File.open($app_capabilities_java, "w") do |f|
        f.puts "package #{JAVA_PACKAGE_NAME};"
        f.puts "public class Capabilities {"
        ANDROID_PERMISSIONS.keys.sort.each do |k|
          f.puts "  public static boolean #{k.upcase}_ENABLED = true;"
        end
        f.puts "}"
      end

      # Generate Push.java
      File.open($app_push_java, "w") do |f|
        f.puts "package #{JAVA_PACKAGE_NAME};"
        f.puts "public class Push {"
        f.puts "  public static final String SENDER = \"#{$push_sender}\";"
        if $push_notifications.nil?
            f.puts "  public static final String PUSH_NOTIFICATIONS =  \"none\";"
        else
            f.puts "  public static final String PUSH_NOTIFICATIONS =  \"#{$push_notifications}\";"
        end
        f.puts "};"
      end

    end

    task :gen_java_ext => "config:android" do
      File.open($app_native_libs_java, "w") do |f|
        f.puts "package #{JAVA_PACKAGE_NAME};"
        f.puts "public class NativeLibraries {"
        f.puts "  public static void load() {"
        f.puts "    // Load native .so libraries"
        Dir.glob($extensionsdir + "/lib*.so").reverse.each do |lib|
          libname = File.basename(lib).gsub(/^lib/, '').gsub(/\.so$/, '')
          f.puts "    System.loadLibrary(\"#{libname}\");"
        end
        f.puts "    // Load native implementation of rhodes"
        f.puts "    System.loadLibrary(\"rhodes\");"
        f.puts "  }"
        f.puts "};"
      end
    end

    task :gensources => [:genconfig, :gen_java_ext]

    task :librhodes => [:libs, :gensources] do
      srcdir = File.join $androidpath, "Rhodes", "jni", "src"
      objdir = File.join $bindir, "libs", $confdir, $ndkabi, $ndkgccver, "librhodes"
      libname = File.join $bindir, "libs", $confdir, $ndkabi, $ndkgccver, "librhodes.so"

      args = []
      args << "-I#{$appincdir}"
      args << "-I#{srcdir}/../include"
      args << "-I#{srcdir}/../include/rhodes/details"
      args << "-I#{$shareddir}"
      args << "-I#{$shareddir}/common"
      args << "-I#{$shareddir}/sqlite"
      args << "-I#{$shareddir}/curl/include"
      args << "-I#{$shareddir}/ruby/include"
      args << "-I#{$shareddir}/ruby/linux"
      args << "-I#{$std_includes}" unless $std_includes.nil?
      args << "-D__SGI_STL_INTERNAL_PAIR_H" if USE_OWN_STLPORT
      args << "-D__NEW__" if USE_OWN_STLPORT
      args << "-I#{$stlport_includes}" if USE_OWN_STLPORT

      cc_build 'librhodes', objdir, args or exit 1

      deps = []
      $libname.each do |k,v|
        deps << v
      end

      args = []
      args << "-L#{$rhobindir}/#{$confdir}/#{$ndkabi}/#{$ndkgccver}"
      args << "-L#{$bindir}/libs/#{$confdir}/#{$ndkabi}/#{$ndkgccver}"
      args << "-L#{$extensionsdir}"

      rlibs = []
      rlibs << "rhomain"
      rlibs << "ruby"
      rlibs << "rhosync"
      rlibs << "rhodb"
      rlibs << "rholog"
      rlibs << "rhocommon"
      rlibs << "json"
      rlibs << "stlport" if USE_OWN_STLPORT
      rlibs << "curl"
      rlibs << "sqlite"
      rlibs << "log"
      rlibs << "dl"
      rlibs << "z"

      rlibs.map! { |x| "-l#{x}" }

      elibs = []
      extlibs = Dir.glob($extensionsdir + "/lib*.a") + Dir.glob($extensionsdir + "/lib*.so")
      stub = []
      extlibs.reverse.each do |f|
        lparam = "-l" + File.basename(f).gsub(/^lib/,"").gsub(/\.(a|so)$/,"")
        elibs << lparam
        # Workaround for GNU ld: this way we have specified one lib multiple times
        # command line so ld's dependency mechanism will find required functions
        # independently of its position in command line
        stub.each do |s|
          args << s
        end
        stub << lparam
      end

      args += elibs
      args += rlibs
      args += elibs
      args += rlibs

  	  mkdir_p File.dirname(libname) unless File.directory? File.dirname(libname)
      cc_link libname, Dir.glob(objdir + "/**/*.o"), args, deps or exit 1

      destdir = File.join($androidpath, "Rhodes", "libs", "armeabi")
      mkdir_p destdir unless File.exists? destdir
      cp_r libname, destdir
      cc_run($stripbin, [File.join(destdir, File.basename(libname))])
    end

 #   desc "Build Rhodes for android"
    task :rhodes => [:rhobundle, :librhodes] do
      javac = $config["env"]["paths"]["java"] + "/javac" + $exe_ext


      set_app_name_android($appname)


      rm_rf $tmpdir + "/Rhodes"
      mkdir_p $tmpdir + "/Rhodes"

      $ext_android_manifest_changes << File.join($extensionsdir, "AndroidManifest.xml")

      app_f = File.new($appmanifest)
      manifest_orig_doc = REXML::Document.new(app_f)
      app_f.close
      dst_manifest =  manifest_orig_doc.elements["manifest"]
      dst_application =  manifest_orig_doc.elements["manifest/application"]
      dst_main_activity = nil
      puts '$$$$$$$$$$$$$$ try to found MainActivity'
      dst_application.elements.each("activity") do |a|
        puts '$$$$$$$$ activity with attr = '+a.attribute('name','android').to_s
        if a.attribute('name','android').to_s == 'com.rhomobile.rhodes.RhodesActivity'
            puts '          $$$ FOUND !'
            dst_main_activity = a
        end
      end

      $ext_android_manifest_changes.each do |m|

        ext_manifest = m
        if File.exists? ext_manifest
          puts 'AndroidManifest.xml['+ext_manifest+'] from native extension found !'

          manifest_ext_doc = REXML::Document.new(File.new(ext_manifest))

          src_manifest =  manifest_ext_doc.elements["manifest"]

          src_application =  manifest_ext_doc.elements["manifest/application"]

          if src_application != nil
              puts 'Extension Manifest process application item :'
              src_application.elements.each do |e|
                  puts '$$$$$$$$ process element with attr = '+e.attribute('name','android').to_s
                  if e.attribute('name','android').to_s == 'com.rhomobile.rhodes.RhodesActivity'
                    e.elements.each do |sube|
                      puts '         add item to MainActivity['+sube.xpath+']'
                      dst_main_activity.add sube
                    end
                  else
                    puts '         add item ['+e.xpath+']'
                    dst_application.add e
                  end
              end
          end

          puts 'Extension Manifest process root <manifest> item :'
          src_manifest.elements.each do |e|
              p = e.xpath
              if p != '/manifest/application'
                    dst_e = manifest_orig_doc.elements[p]
                    if dst_e != nil
                          if p == '/manifest/uses-sdk'
                              puts '         found and delete original item ['+p+']'
                              manifest_orig_doc.elements.delete p
                          end
                    end
                    puts '         and new item ['+p+']'
                    dst_manifest.add e
              end
          end

        else
          puts 'AndroidManifest change file ['+m+'] from native extension not found !'
        end

      end

      #puts 'Result Manifest :'
      #manifest_orig_doc.elements['manifest'].elements.each do |e|
      #   puts '     + '+e.xpath
      #   if e.xpath == '/manifest/application'
      #       manifest_orig_doc.elements['manifest/application'].elements.each do |t|
      #             puts '              + '+t.xpath
      #       end
      #   end
      #end

      puts 'delete original manifest'
      File.delete($appmanifest)

      updated_f = File.open($appmanifest, "w")
      manifest_orig_doc.write updated_f, 2
      updated_f.close

      #rm tappmanifest
      puts 'Manifest updated by extension saved!'


      # RhodesActivity Listeners
      f = StringIO.new("", "w+")
      f.puts '// WARNING! THIS FILE IS GENERATED AUTOMATICALLY! DO NOT EDIT IT MANUALLY!'
      f.puts 'package com.rhomobile.rhodes;'
      f.puts ''
      f.puts 'import com.rhomobile.rhodes.phonebook.ContactAccessor;'
      f.puts ''
      f.puts 'class RhodesActivityStartupListeners {'
      f.puts ''
      f.puts '	public static final String[] ourRunnableList = { ""'
      $ext_android_rhodes_activity_listener.each do |a|
         f.puts '       ,"'+a+'"'
      end
      f.puts '	};'
      f.puts ''
      f.puts '}'
      Jake.modify_file_if_content_changed(File.join($startdir, "platform","android","Rhodes","src","com","rhomobile","rhodes","RhodesActivityStartupListeners.java"), f)


      puts 'EXT:  add additional files to project before build'
      $ext_android_resources_addons.each do |r|
         puts 'add resources from extension copy ['+r+'] to ['+$tmpdir+']'
          Dir.foreach(r) do |f|
             cp = File.join(r, f)
             if ((File.directory?(cp)) || (File.file?(cp))) && ((f != '.') && ( f != '..'))
                cp_r cp,$tmpdir
             end
          end
      end

      generate_rjava

      mkdir_p File.join($app_rjava_dir, "R") if not File.exists? File.join($app_rjava_dir, "R")
      buf = File.new(File.join($app_rjava_dir, "R.java"),"r").read.gsub(/^\s*package\s*#{$app_package_name};\s*$/,"\npackage com.rhomobile.rhodes;\n")
      File.open(File.join($app_rjava_dir, "R", "R.java"),"w") { |f| f.write(buf) }


      srclist = File.join($builddir, "RhodesSRC_build.files")
      newsrclist = File.join($tmpdir, "RhodesSRC_build.files")
      lines = []
      File.open(srclist, "r") do |f|
        while line = f.gets
          line.chomp!
          next if line =~ /\/AndroidR\.java\s*$/

		      if !$use_geomapping
			        next if line == "platform/android/Rhodes/src/com/rhomobile/rhodes/mapview/GoogleMapView.java"
			        next if line == "platform/android/Rhodes/src/com/rhomobile/rhodes/mapview/AnnotationsOverlay.java"
		      end

          #next if !$use_geomapping and line =~ /\/GoogleMapView\//
          #next if !$use_geomapping and line =~ /\/AnnotationsOverlay\//

          lines << line
        end
      end
      lines << "\"" +File.join($app_rjava_dir, "R.java")+"\""
      lines << "\"" +File.join($app_rjava_dir, "R", "R.java")+"\""
      lines << "\"" +$app_android_r+"\""
      lines << "\"" +$app_native_libs_java+"\""
      lines << "\"" +$app_capabilities_java+"\""
      lines << "\"" +$app_push_java+"\""
      if File.exists? File.join($extensionsdir, "ext_build.files")
        puts 'ext_build.files found ! Addditional files for compilation :'
        File.open(File.join($extensionsdir, "ext_build.files")) do |f|
          while line = f.gets
            line.chomp!
            puts 'java file : ' + line
            lines << "\""+line+"\""
          end
        end
      else
        puts 'ext_build.files not found - no additional java files for compilation'
      end

      # process collected ext src files
      puts 'process additional java files for build from extensions :'
      $ext_android_additional_sources_list.each do |s|
        s.chomp!
        puts 'java file : ' + s
        lines << "\""+s+"\""
      end

      File.open(newsrclist, "w") { |f| f.write lines.join("\n") }
      srclist = newsrclist

      args = []
      args << "-g"
      args << "-d"
      args << $tmpdir + '/Rhodes'
      args << "-source"
      args << "1.6"
      args << "-target"
      args << "1.6"
      args << "-nowarn"
      args << "-encoding"
      args << "latin1"
      args << "-classpath"
      classpath = $androidjar
      classpath += $path_separator + $gapijar unless $gapijar.nil?
      classpath += $path_separator + "#{$tmpdir}/Rhodes"
      Dir.glob(File.join($extensionsdir, "*.jar")).each do |f|
        classpath += $path_separator + f
      end
      args << classpath
      args << "@#{srclist}"
      puts Jake.run(javac, args)
      unless $?.success?
        puts "Error compiling java code"
        exit 1
      end

      files = []
      Dir.glob(File.join($extensionsdir, "*.jar")).each do |f|
        puts Jake.run($jarbin, ["xf", f], File.join($tmpdir, "Rhodes"))
        unless $?.success?
          puts "Error running jar (xf)"
          exit 1
        end
      end
      Dir.glob(File.join($tmpdir, "Rhodes", "*")).each do |f|
        relpath = Pathname.new(f).relative_path_from(Pathname.new(File.join($tmpdir, "Rhodes"))).to_s
        files << relpath
      end
      unless files.empty?
        args = ["cf", "../../Rhodes.jar"]
        args += files
        puts Jake.run($jarbin, args, File.join($tmpdir, "Rhodes"))
        unless $?.success?
          puts "Error running jar"
          exit 1
        end
      end
    end

    #desc "build all"
    task :all => [:rhobundle, :rhodes]
  end
end

namespace "package" do
  task :android => "build:android:all" do
    puts "Running dx utility"
    args = []
    args << "-jar"
    args << $dxjar
    args << "--dex"
    args << "--output=#{$bindir}/classes.dex"
    args << "#{$bindir}/Rhodes.jar"
    puts Jake.run("java", args)
    unless $?.success?
      puts "Error running DX utility"
      exit 1
    end

    manifest = $appmanifest
    resource = $appres
    assets = Jake.get_absolute $androidpath + "/Rhodes/assets"
    resourcepkg =  $bindir + "/rhodes.ap_"

    puts "Packaging Assets and Jars"

    # this task already caaled during build "build:android:all"
    #set_app_name_android($appname)

    args = ["package", "-f", "-M", manifest, "-S", resource, "-A", assets, "-I", $androidjar, "-F", resourcepkg]
    puts Jake.run($aapt, args)
    unless $?.success?
      puts "Error running AAPT (1)"
      exit 1
    end

    # Workaround: manually add files starting with '_' because aapt silently ignore such files when creating package
    rm_rf File.join($tmpdir, "assets")
    cp_r assets, $tmpdir
    Dir.glob(File.join($tmpdir, "assets/**/*")).each do |f|
      next unless File.basename(f) =~ /^_/
      relpath = Pathname.new(f).relative_path_from(Pathname.new($tmpdir)).to_s
      puts "Add #{relpath} to #{resourcepkg}..."
      args = ["uf", resourcepkg, relpath]
      puts Jake.run($jarbin, args, $tmpdir)
      unless $?.success?
        puts "Error running AAPT (2)"
        exit 1
      end
    end

    # Add native librhodes.so
    rm_rf File.join($tmpdir, "lib")
    mkdir_p File.join($tmpdir, "lib/armeabi")
    cp_r File.join($bindir, "libs", $confdir, $ndkabi, $ndkgccver, "librhodes.so"), File.join($tmpdir, "lib/armeabi")
    # Add extensions .so libraries
    Dir.glob($extensionsdir + "/lib*.so").each do |lib|
      cp_r lib, File.join($tmpdir, "lib/armeabi")
    end
    args = ["uf", resourcepkg]
    # Strip them all to decrease size
    Dir.glob($tmpdir + "/lib/armeabi/lib*.so").each do |lib|
      cc_run($stripbin, [lib])
      args << "lib/armeabi/#{File.basename(lib)}"
    end
    puts Jake.run($jarbin, args, $tmpdir)
    err = $?
    rm_rf $tmpdir + "/lib"
    unless err.success?
      puts "Error running AAPT (3)"
      exit 1
    end
  end
end

namespace "device" do
  namespace "android" do

    desc "Build debug self signed for device"
    task :debug => "package:android" do
      dexfile =  $bindir + "/classes.dex"
      simple_apkfile =  $targetdir + "/" + $appname + "-tmp.apk"
      final_apkfile =  $targetdir + "/" + $appname + "-debug.apk"
      resourcepkg =  $bindir + "/rhodes.ap_"

      apk_build $androidsdkpath, simple_apkfile, resourcepkg, dexfile, true
      
      puts "Align Debug APK file"
      args = []
      args << "-f"
      args << "-v"
      args << "4"
      args << simple_apkfile
      args << final_apkfile
      puts Jake.run($zipalign, args)
      unless $?.success?
        puts "Error running zipalign"
        exit 1
      end
      #remove temporary files
      rm_rf simple_apkfile

      File.open(File.join(File.dirname(final_apkfile), "app_info.txt"), "w") do |f|
        f.puts $app_package_name
      end

    end

    task :install => :debug do
      apkfile = $targetdir + "/" + $appname + "-debug.apk"
      puts "Install APK file"
      Jake.run($adb, ["-d", "install", "-r", apkfile])
      unless $?.success?
        puts "Error installing APK file"
        exit 1
      end
      puts "Install complete"
    end

    desc "Build production signed for device"
    task :production => "package:android" do
      dexfile =  $bindir + "/classes.dex"
      simple_apkfile =  $targetdir + "/" + $appname + "_tmp.apk"
      final_apkfile =  $targetdir + "/" + $appname + "_signed.apk"
      signed_apkfile =  $targetdir + "/" + $appname + "_tmp_signed.apk"
      resourcepkg =  $bindir + "/rhodes.ap_"

      apk_build $androidsdkpath, simple_apkfile, resourcepkg, dexfile, false

      if not File.exists? $keystore
        puts "Generating private keystore..."
        mkdir_p File.dirname($keystore) unless File.directory? File.dirname($keystore)

        args = []
        args << "-genkey"
        args << "-alias"
        args << $storealias
        args << "-keyalg"
        args << "RSA"
        args << "-validity"
        args << "20000"
        args << "-keystore"
        args << $keystore
        args << "-storepass"
        args << $storepass
        args << "-keypass"
        args << $keypass
        puts Jake.run($keytool, args)
        unless $?.success?
          puts "Error generating keystore file"
          exit 1
        end
      end

      puts "Signing APK file"
      args = []
      args << "-verbose"
      args << "-keystore"
      args << $keystore
      args << "-storepass"
      args << $storepass
      args << "-signedjar"
      args << signed_apkfile
      args << simple_apkfile
      args << $storealias
      puts Jake.run($jarsigner, args)
      unless $?.success?
        puts "Error running jarsigner"
        exit 1
      end

      puts "Align APK file"
      args = []
      args << "-f"
      args << "-v"
      args << "4"
      args << '"' + signed_apkfile + '"'
      args << '"' + final_apkfile + '"'
      puts Jake.run($zipalign, args)
      unless $?.success?
        puts "Error running zipalign"
        exit 1
      end
      #remove temporary files
      rm_rf simple_apkfile
      rm_rf signed_apkfile

      File.open(File.join(File.dirname(final_apkfile), "app_info.txt"), "w") do |f|
        f.puts $app_package_name
      end
    end

    task :getlog => "config:android" do
      AndroidTools.get_app_log($appname, true) or exit 1
    end
  end
end

namespace "emulator" do
  namespace "android" do
    task :getlog => "config:android" do
      AndroidTools.get_app_log($appname, false) or exit 1
    end
  end
end

namespace "android" do
    task :get_log => "config:android" do
		puts "log_file=" + $applog_path
	end
end

namespace "run" do
  namespace "android" do
    
    task :spec => ["device:android:debug"] do

        log_name  = $app_path + '/RhoLogSpec.txt'
        File.delete(log_name) if File.exist?(log_name)

        AndroidTools.logclear($device_flag)
        run_emulator( :hidden => true ) if $device_flag == '-e'
        do_uninstall($device_flag)
        
        # Failsafe to prevent eternal hangs
        Thread.new {
          sleep 2000
          AndroidTools.kill_adb_and_emulator
        }

        load_app_and_run($device_flag)
        AndroidTools.logcat($device_flag, log_name)

        Jake.before_run_spec
        start = Time.now

        puts "waiting for application"

        for i in 0..60
            if AndroidTools.application_running($device_flag, $app_package_name)
                break
            else
                sleep(1)
            end
        end

        puts "waiting for log: " + log_name
        
        for i in 0..120
			if !File.exist?(log_name)
				sleep(1)
			else
				break
			end
        end

		if !File.exist?(log_name)
            puts "Can not read log file: " + log_name
			exit(1)
        end

        puts "start read log"
        
        end_spec = false
        while !end_spec do
            io = File.new(log_name, "r")
        
            io.each do |line|
                #puts line
                
                end_spec = !Jake.process_spec_output(line)
                break if end_spec
            end
            io.close
            
            break unless AndroidTools.application_running($device_flag, $app_package_name)
            sleep(5) unless end_spec
        end

        Jake.process_spec_results(start)        
        
        # stop app
        do_uninstall($device_flag)
        kill_adb

        $stdout.flush
    end

    task :phone_spec => "phone_spec:emulator"

    task :framework_spec => "framework_spec:emulator"

    namespace "phone_spec" do
      task :device do
        $device_flag = "-d"
        exit Jake.run_spec_app('android','phone_spec')
      end

      task :emulator do
        $device_flag = "-e"
        exit Jake.run_spec_app('android','phone_spec')
      end
    end

    namespace "framework_spec" do
      task :device do
        $device_flag = "-d"
        exit Jake.run_spec_app('android','framework_spec')
      end

      task :emulator do
        $device_flag = "-e"
        exit Jake.run_spec_app('android','framework_spec')
      end
    end

    task :emulator => "device:android:debug" do
        run_emulator
        load_app_and_run
    end

    task :rhosimulator => "config:common" do    
    
        $emuversion = $app_config["android"]["version"] unless $app_config["android"].nil?
        $emuversion = $config["android"]["version"] if $emuversion.nil? and !$config["android"].nil?
    
        $rhosim_config = "platform='android'\r\n"
        $rhosim_config += "os_version='#{$emuversion}'\r\n" if $emuversion
        
        Rake::Task["run:rhosimulator"].invoke            
    end

    task :get_info => "config:android" do
        $androidtargets.each do |level|
            puts "#{get_market_version(level[0])}"
        end

        emu_version = $emuversion
        
        puts ""        
        cur_name = ""
        
        `"#{$androidbin}" list avd`.split(/\n/).each do |line|
            line.each_line do |item|
                ar = item.split(':')
                ar[0].strip!
                if ar[0] == "Name"
                    cur_name = ar[1].strip!
                    puts "#{cur_name}"
                end
                
                if $appavdname && cur_name == $appavdname && (ar[0] == "Target" || ar.length == 1)
                    
                    text = ar[0] == "Target" ? ar[1] : ar[0]
                    
                    nAnd = text.index("Android")
                    if nAnd
                        nAnd = text.index(" ", nAnd)
                        nAnd1 = text.index("-", nAnd+1)                    
                        nAnd1 = text.index(" ", nAnd+1) unless nAnd1
                        emu_version = text[nAnd+1, nAnd1-nAnd-1]
                    end    
                end
                
            end    
        end

        puts ""

        puts "#{emu_version}"
        puts "#{$appavdname}"

    end

    def  kill_adb
        # stop app
        if RUBY_PLATFORM =~ /(win|w)32$/
          # Windows
          `taskkill /F /IM adb.exe`
        else
          `killall -9 adb`
        end
    end

    def  run_emulator(options = {})
      apkfile = Jake.get_absolute $targetdir + "/" + $appname + "-debug.apk"

      kill_adb
      Jake.run($adb, ['start-server'], nil, true)
      puts 'Sleep for 5 sec. waiting for "adb start-server"'
      sleep 5

      AndroidTools.logcat_process()

      if $appavdname != nil
        $avdname = $appavdname
      end

      createavd = "\"#{$androidbin}\" create avd --name #{$avdname} --target #{$avdtarget} --sdcard 32M "
      system("echo no | #{createavd}") unless File.directory?( File.join(ENV['HOME'], ".android", "avd", "#{$avdname}.avd" ) )

      if $use_google_addon_api
        avdini = File.join(ENV['HOME'], '.android', 'avd', "#{$avdname}.ini")
        avd_using_gapi = true if File.new(avdini).read =~ /:Google APIs:/
        unless avd_using_gapi
          puts "Can not use specified AVD (#{$avdname}) because of incompatibility with Google APIs. Delete it and try again."
          exit 1
        end
      end

      running = AndroidTools.is_emulator_running

      if !running
        # Start the emulator, check on it every 5 seconds until it's running
        cmd = "\"#{$emulator}\" -cpu-delay 0 -no-boot-anim"
        cmd << " -no-window" if options[:hidden]
        cmd << " -avd #{$avdname}"
        Thread.new { system(cmd) }
        puts "Waiting up to 180 seconds for emulator..."
        startedWaiting = Time.now
        adbRestarts = 1
        while (Time.now - startedWaiting < 180 )
          sleep 5
          now = Time.now
          started = false
          Jake.run2 $adb, ["-e", "shell", "ps"], :system => false, :hideerrors => false do |line|
            started = true if line =~ /android\.process\.acore/
            true
          end
          unless started
            printf("%.2fs: ",(now - startedWaiting))
            if (now - startedWaiting) > (60 * adbRestarts)
              # Restart the adb server every 60 seconds to prevent eternal waiting
              puts "Appears hung, restarting adb server"
              kill_adb
              Jake.run($adb, ['start-server'], nil, true)
              adbRestarts += 1

              AndroidTools.logcat_process()
            else
              puts "Still waiting..."
            end
          else
            puts "Success"
            puts "Device is ready after " + (Time.now - startedWaiting).to_s + " seconds"
            break
          end
        end

        if !AndroidTools.is_emulator_running
          puts "Emulator still isn't up and running, giving up"
          exit 1
        end

      else
        puts "Emulator is up and running"
      end

      $stdout.flush
    end
    
    def  load_app_and_run(device_flag = '-e')
      puts "Loading package"
      apkfile = Jake.get_absolute $targetdir + "/" + $appname + "-debug.apk"
      count = 0
      done = false
      while count < 20
        f = Jake.run2($adb, [device_flag, "install", "-r", apkfile], {:nowait => true})
        theoutput = ""
        while c = f.getc
          $stdout.putc c
          $stdout.flush
          theoutput << c
        end
        f.close

        if theoutput.to_s.match(/Success/)
          done = true
          break
        end

        puts "Failed to load (possibly because emulator not done launching)- retrying"
        $stdout.flush
        sleep 1
        count += 1
      end

      puts "Loading complete, starting application.." if done
      AndroidTools.run_application(device_flag) if done
    end

    desc "build and install on device"
    task :device => "device:android:install" do
      puts "Starting application..."
      AndroidTools.run_application("-d")
      
      AndroidTools.logcat_process("-d")
    end
  end

  desc "build and launch emulator"
  task :android => "run:android:emulator" do
  end
end

namespace "uninstall" do
  def do_uninstall(flag)
    args = []
    args << flag
    args << "uninstall"
    args << $app_package_name
    for i in 0..20
		result = Jake.run($adb, args)
		unless $?.success?
			puts "Error uninstalling application"
			exit 1
		end

		if result.include?("Success")
			puts "Application uninstalled successfully"
			break
		else
			if result.include?("Failure")					
				puts "Application is not installed on the device"
				break
			else		
				puts "Error uninstalling application"
				exit 1 if i == 20
			end
		end
		sleep(5)
    end
    
  end

  namespace "android" do
    task :emulator => "config:android" do
      unless AndroidTools.is_emulator_running
        puts "WARNING!!! Emulator is not up and running"
        exit 1
      end
      do_uninstall('-e')
    end

    desc "uninstall from device"
    task :device => "config:android" do
      unless AndroidTools.is_device_running
        puts "WARNING!!! Device is not connected"
        exit 1
      end
      do_uninstall('-d')
    end
  end

  desc "uninstall from emulator"
  task :android => "uninstall:android:emulator" do
  end
end

namespace "clean" do
  desc "Clean Android"
  task :android => "clean:android:all"
  namespace "android" do
    task :assets => "config:android" do
      Dir.glob($androidpath + "/Rhodes/assets/**/*") do |f|
        rm f, :force => true unless f =~ /\/loading\.html$/
      end
    end
    task :files => "config:android" do
      rm_rf $targetdir
      rm_rf $bindir
      rm_rf $srcdir
      rm_rf $libs
    end
  task :libsqlite => "config:android" do
    cc_clean "sqlite"
  end
  task :libs => ["config:android"] do
    $native_libs.each do |l|
      cc_clean l
    end
  end
  task :librhodes => "config:android" do
    rm_rf $rhobindir + "/" + $confdir + "/" + $ndkabi + "/" + $ndkgccver + "/librhodes"
    rm_rf $bindir + "/libs/" + $confdir + "/" + $ndkabi + "/" + $ndkgccver + "/librhodes.so"
  end
#  desc "clean android"
  task :all => [:assets,:librhodes,:libs,:files]
  end
end

