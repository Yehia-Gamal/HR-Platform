from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'apps' / 'mobile_flutter'
manifest = root / 'android' / 'app' / 'src' / 'main' / 'AndroidManifest.xml'
if manifest.exists():
    text = manifest.read_text()
    permissions = [
        '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
        '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
        '<uses-permission android:name="android.permission.CAMERA" />',
    ]
    marker = '<manifest'
    close = text.find('>', text.find(marker)) + 1
    for permission in reversed(permissions):
        if permission not in text:
            text = text[:close] + '\n    ' + permission + text[close:]

    intent_filter = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="ahlashabab" android:host="action" />
            </intent-filter>'''
    if 'android:scheme="ahlashabab"' not in text:
        text = text.replace('</activity>', intent_filter + '\n        </activity>')
    manifest.write_text(text)

for gradle_name in ('build.gradle.kts', 'build.gradle'):
    gradle = root / 'android' / 'app' / gradle_name
    if not gradle.exists():
        continue
    text = gradle.read_text()
    if gradle_name.endswith('.kts'):
        text = text.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
        # flutter_secure_storage compiles against SDK 36 (backward compatible).
        text = text.replace('compileSdk = flutter.compileSdkVersion',
                            'compileSdk = 36')
        # Pin the NDK to the highest version the bundled plugins request
        # (passkeys/geolocator/camera/etc. require 27.0.12077973; backward compatible).
        text = text.replace('ndkVersion = flutter.ndkVersion',
                            'ndkVersion = "27.0.12077973"')
        # flutter_local_notifications requires core library desugaring.
        if 'isCoreLibraryDesugaringEnabled' not in text:
            text = text.replace(
                'compileOptions {',
                'compileOptions {\n        isCoreLibraryDesugaringEnabled = true',
                1)
        if 'coreLibraryDesugaring(' not in text:
            text = text.rstrip() + (
                '\n\ndependencies {\n'
                '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
                '}\n')
    else:
        text = text.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
        text = text.replace('compileSdkVersion flutter.compileSdkVersion',
                            'compileSdkVersion 36')
        text = text.replace('ndkVersion flutter.ndkVersion',
                            'ndkVersion "27.0.12077973"')
    gradle.write_text(text)

plist = root / 'ios' / 'Runner' / 'Info.plist'
if plist.exists():
    text = plist.read_text()
    entries = {
        'NSLocationWhenInUseUsageDescription': 'يحتاج التطبيق إلى موقعك لتنفيذ الحضور أو الاستجابة لطلب موقع واضح ومحدد المدة.',
        'NSCameraUsageDescription': 'تستخدم الكاميرا لتسجيل فيديو تحقق صامت مدته خمس ثوانٍ بعد موافقتك.',
    }
    insertion = ''
    for key, value in entries.items():
        if f'<key>{key}</key>' not in text:
            insertion += f'\n\t<key>{key}</key>\n\t<string>{value}</string>'
    if '<key>CFBundleURLTypes</key>' not in text:
        insertion += '''
\t<key>CFBundleURLTypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleURLName</key>
\t\t\t<string>org.ahlashabab.management</string>
\t\t\t<key>CFBundleURLSchemes</key>
\t\t\t<array><string>ahlashabab</string></array>
\t\t</dict>
\t</array>'''
    if insertion:
        text = text.replace('\n</dict>', insertion + '\n</dict>')
        plist.write_text(text)

print('Flutter platform configuration applied.')
