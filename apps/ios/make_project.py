from pathlib import Path
import plistlib
root = Path(__file__).parent
files = sorted((root/'ZeroRed').glob('*.swift'))
ids = {p.name: (f'{i+100:024X}', f'{i+200:024X}') for i,p in enumerate(files)}
objects=[]
def obj(i, s): objects.append(f'{i} = {{ {s} }};')
for p in files:
    build, ref=ids[p.name]
    obj(build, f'isa = PBXBuildFile; fileRef = {ref};')
    obj(ref, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {p.name}; sourceTree = "<group>";')
obj('A00000000000000000000001','isa = PBXFileReference; explicitFileType = wrapper.application; path = ZeroRed.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('A00000000000000000000002','isa = PBXGroup; children = (A00000000000000000000003, A00000000000000000000004, D00000000000000000000003); sourceTree = "<group>";')
obj('A00000000000000000000003','isa = PBXGroup; path = ZeroRed; sourceTree = "<group>"; children = ('+', '.join(x[1] for x in ids.values())+');')
obj('A00000000000000000000004','isa = PBXGroup; name = Products; sourceTree = "<group>"; children = (A00000000000000000000001, D00000000000000000000004);')
obj('A00000000000000000000005','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+', '.join(x[0] for x in ids.values())+'); runOnlyForDeploymentPostprocessing = 0;')
obj('A00000000000000000000006','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (F00000000000000000000003); runOnlyForDeploymentPostprocessing = 0;')
obj('A00000000000000000000007','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('A00000000000000000000008','isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000010; buildPhases = (A00000000000000000000005,A00000000000000000000006,A00000000000000000000007); buildRules = (); dependencies = (); name = ZeroRed; packageProductDependencies = (F00000000000000000000002); productName = ZeroRed; productReference = A00000000000000000000001; productType = "com.apple.product-type.application";')
obj('A00000000000000000000009','isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }; buildConfigurationList = A00000000000000000000011; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,"zh-Hans",Base); mainGroup = A00000000000000000000002; productRefGroup = A00000000000000000000004; projectDirPath = ""; projectRoot = ""; packageReferences = (F00000000000000000000001); targets = (A00000000000000000000008, D00000000000000000000008);')
for i, name in enumerate(['Debug','Release']):
    opt='-Onone' if name=='Debug' else '-O'
    conditions = 'DEBUG' if name == 'Debug' else ''
    active_arch = 'YES' if name == 'Debug' else 'NO'
    obj(f'B{i:023X}',f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; ONLY_ACTIVE_ARCH = {active_arch}; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "{conditions}"; SWIFT_OPTIMIZATION_LEVEL = "{opt}"; }};')
    obj(f'C{i:023X}',f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.zerored.browser; INFOPLIST_FILE = ZeroRed/Info.plist; GENERATE_INFOPLIST_FILE = NO; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 2; MARKETING_VERSION = 0.2; SWIFT_EMIT_LOC_STRINGS = YES; }};')
obj('A00000000000000000000010','isa = XCConfigurationList; buildConfigurations = (C00000000000000000000000,C00000000000000000000001); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('A00000000000000000000011','isa = XCConfigurationList; buildConfigurations = (B00000000000000000000000,B00000000000000000000001); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('D00000000000000000000001', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ZeroRedUITests.swift; sourceTree = "<group>";')
obj('D00000000000000000000002', 'isa = PBXBuildFile; fileRef = D00000000000000000000001;')
obj('D00000000000000000000003', 'isa = PBXGroup; path = UITests; sourceTree = "<group>"; children = (D00000000000000000000001);')
obj('D00000000000000000000004', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ZeroRedUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj('D00000000000000000000005', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (D00000000000000000000002); runOnlyForDeploymentPostprocessing = 0;')
obj('D00000000000000000000006', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('D00000000000000000000007', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('D00000000000000000000008', 'isa = PBXNativeTarget; name = ZeroRedUITests; productName = ZeroRedUITests; productReference = D00000000000000000000004; productType = "com.apple.product-type.bundle.ui-testing"; buildConfigurationList = D00000000000000000000010; buildPhases = (D00000000000000000000005,D00000000000000000000006,D00000000000000000000007); buildRules = (); dependencies = (D00000000000000000000009);')
obj('D00000000000000000000009', 'isa = PBXTargetDependency; target = A00000000000000000000008; targetProxy = D00000000000000000000011;')
obj('D00000000000000000000011', 'isa = PBXContainerItemProxy; containerPortal = A00000000000000000000009; proxyType = 1; remoteGlobalIDString = A00000000000000000000008; remoteInfo = ZeroRed;')
for i, name in enumerate(['Debug','Release']):
    obj(f'E{i:023X}', f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.zerored.browser.uitests; GENERATE_INFOPLIST_FILE = YES; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; TEST_TARGET_NAME = ZeroRed; }};')
obj('D00000000000000000000010', 'isa = XCConfigurationList; buildConfigurations = (E00000000000000000000000,E00000000000000000000001); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('F00000000000000000000001', 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/weichsel/ZIPFoundation.git"; requirement = { kind = exactVersion; version = 0.9.19; };')
obj('F00000000000000000000002', 'isa = XCSwiftPackageProductDependency; package = F00000000000000000000001; productName = ZIPFoundation;')
obj('F00000000000000000000003', 'isa = PBXBuildFile; productRef = F00000000000000000000002;')
(root/'ZeroRed.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = A00000000000000000000009; }\n')
info={'CFBundleDisplayName':'zero red','CFBundleName':'$(PRODUCT_NAME)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'NSAppTransportSecurity':{'NSAllowsArbitraryLoadsInWebContent':True,'NSAllowsLocalNetworking':True},'CFBundleLocalizations':['en','zh-Hans']}
info.update({
    'NSCameraUsageDescription':'允许你在网页中拍照、上传或进行视频通话。 / Use the camera on websites you authorize.',
    'NSMicrophoneUsageDescription':'允许你在网页中录音或进行语音通话。 / Use the microphone on websites you authorize.',
    'NSPhotoLibraryUsageDescription':'选择照片上传到你正在使用的网站。 / Select photos to upload to websites.',
    'NSLocationWhenInUseUsageDescription':'向你授权的网站提供当前位置。 / Share location with websites you authorize.',
    'UIBackgroundModes':['audio'],
    'LSSupportsOpeningDocumentsInPlace':True,
    'CFBundleURLTypes':[{'CFBundleURLName':'com.zerored.browser','CFBundleURLSchemes':['zerored']}],
    'CFBundleDocumentTypes':[{'CFBundleTypeName':'Reading documents','CFBundleTypeRole':'Viewer','LSHandlerRank':'Alternate','LSItemContentTypes':['public.plain-text','public.html','com.adobe.pdf','org.openxmlformats.wordprocessingml.document']}]
})
(root/'ZeroRed/Info.plist').write_bytes(plistlib.dumps(info))
