#!/usr/bin/env python3
"""向 Flutter iOS 工程添加 VpnExtension Packet Tunnel 目标（幂等）。"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PBX = ROOT / "ios/Runner.xcodeproj/project.pbxproj"

MARKER = "/* VpnExtension target (auto) */"

FILES = {
    "IOSVPNREF01": ("VpnConstants.swift", "Shared/VpnConstants.swift"),
    "IOSVPNREF02": ("VpnTunnelManager.swift", "Runner/VpnTunnelManager.swift"),
    "IOSVPNREF03": ("PacketTunnelProvider.swift", "VpnExtension/PacketTunnelProvider.swift"),
    "IOSVPNREF04": ("Info.plist", "VpnExtension/Info.plist"),
    "IOSVPNREF05": ("VpnExtension.entitlements", "VpnExtension/VpnExtension.entitlements"),
    "IOSVPNREF06": ("Runner.entitlements", "Runner/Runner.entitlements"),
    "IOSVPNREF07": ("VpnExtension.appex", "VpnExtension.appex", "wrapper.app-extension"),
}


def main() -> int:
    text = PBX.read_text(encoding="utf-8")
    if MARKER in text:
        print("VpnExtension 已存在，跳过")
        return 0

    file_refs = "\n".join(
        f"\t\t{k} /* {v[0]} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = {v[2] if len(v) > 2 else 'sourcecode.swift'}; "
        f"path = {v[1]}; sourceTree = \"<group>\"; }};"
        for k, v in FILES.items()
    )

    build_files = "\n".join(
        f"\t\tIOSVPNBLD{k[-2:]} /* {FILES[k][0]} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {k} /* {FILES[k][0]} */; }};"
        for k in ("IOSVPNREF01", "IOSVPNREF02", "IOSVPNREF03")
    )
    build_files += (
        "\n\t\tIOSVPNBLD04 /* VpnExtension.appex in Embed App Extensions */ = "
        "{isa = PBXBuildFile; fileRef = IOSVPNREF07 /* VpnExtension.appex */; "
        "settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };"
    )

    embed_phase = f"""
\t\tIOSVPNEMBED01 /* Embed App Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\tIOSVPNBLD04 /* VpnExtension.appex in Embed App Extensions */,
\t\t\t);
\t\t\tname = "Embed App Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""

    extension_target = f"""
\t\tIOSVPNTGT01 /* VpnExtension */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = IOSVPNCFG01 /* Build configuration list for VpnExtension */;
\t\t\tbuildPhases = (
\t\t\t\tIOSVPNSRC01 /* Sources */,
\t\t\t\tIOSVPNFRM01 /* Frameworks */,
\t\t\t\tIOSVPNRES01 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = VpnExtension;
\t\t\tproductName = VpnExtension;
\t\t\tproductReference = IOSVPNREF07 /* VpnExtension.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};"""

    dep = """
\t\tIOSVPNDEP01 /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = IOSVPNTGT01 /* VpnExtension */;
\t\t\ttargetProxy = IOSVPNPRX01 /* PBXContainerItemProxy */;
\t\t};"""

    proxy = """
\t\tIOSVPNPRX01 /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 97C146E61CF9000F007C117D /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = IOSVPNTGT01;
\t\t\tremoteInfo = VpnExtension;
\t\t};"""

    groups = """
\t\tIOSVPNGRP01 /* Shared */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tIOSVPNREF01 /* VpnConstants.swift */,
\t\t\t);
\t\t\tpath = Shared;
\t\t\tsourceTree = "<group>";
\t\t};
\t\tIOSVPNGRP02 /* VpnExtension */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tIOSVPNREF03 /* PacketTunnelProvider.swift */,
\t\t\t\tIOSVPNREF04 /* Info.plist */,
\t\t\t\tIOSVPNREF05 /* VpnExtension.entitlements */,
\t\t\t);
\t\t\tpath = VpnExtension;
\t\t\tsourceTree = "<group>";
\t\t};"""

    ext_configs = """
\t\tIOSVPNCFG02 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = VpnExtension/VpnExtension.entitlements;
\t\t\t\tCURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
\t\t\t\tINFOPLIST_FILE = VpnExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.kele.keleVpn.VpnExtension;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\tIOSVPNCFG03 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = VpnExtension/VpnExtension.entitlements;
\t\t\t\tCURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
\t\t\t\tINFOPLIST_FILE = VpnExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.kele.keleVpn.VpnExtension;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\tIOSVPNCFG04 /* Profile */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = VpnExtension/VpnExtension.entitlements;
\t\t\t\tCURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
\t\t\t\tINFOPLIST_FILE = VpnExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.kele.keleVpn.VpnExtension;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Profile;
\t\t};
\t\tIOSVPNCFG01 /* Build configuration list for VpnExtension */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\tIOSVPNCFG02 /* Debug */,
\t\t\t\tIOSVPNCFG03 /* Release */,
\t\t\t\tIOSVPNCFG04 /* Profile */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};"""

    # Inject sections
    text = text.replace(
        "/* End PBXBuildFile section */",
        build_files + "\n" + MARKER + "\n/* End PBXBuildFile section */",
    )
    text = text.replace(
        "/* End PBXFileReference section */",
        file_refs + "\n/* End PBXFileReference section */",
    )
    text = text.replace(
        "/* End PBXContainerItemProxy section */",
        proxy + "\n/* End PBXContainerItemProxy section */",
    )
    text = text.replace(
        "/* End PBXCopyFilesBuildPhase section */",
        embed_phase + "\n/* End PBXCopyFilesBuildPhase section */",
    )
    text = text.replace(
        "\t\t97C146F01CF9000F007C117D /* Runner */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (",
        "\t\t97C146F01CF9000F007C117D /* Runner */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tIOSVPNREF02 /* VpnTunnelManager.swift */,\n\t\t\t\tIOSVPNREF06 /* Runner.entitlements */,",
    )
    text = text.replace(
        "\t\t97C146E51CF9000F007C117D = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (",
        "\t\t97C146E51CF9000F007C117D = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tIOSVPNGRP01 /* Shared */,\n\t\t\t\tIOSVPNGRP02 /* VpnExtension */,",
    )
    text = text.replace(
        "\t\t97C146EF1CF9000F007C117D /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (",
        "\t\t97C146EF1CF9000F007C117D /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tIOSVPNREF07 /* VpnExtension.appex */,",
    )
    text = text.replace("/* End PBXGroup section */", groups + "\n/* End PBXGroup section */")
    text = text.replace(
        "/* End PBXNativeTarget section */",
        extension_target + "\n/* End PBXNativeTarget section */",
    )
    text = text.replace(
        "\t\t97C146ED1CF9000F007C117D /* Runner */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = 97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget \"Runner\" */;\n\t\t\tbuildPhases = (",
        "\t\t97C146ED1CF9000F007C117D /* Runner */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = 97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget \"Runner\" */;\n\t\t\tbuildPhases = (\n\t\t\t\tIOSVPNEMBED01 /* Embed App Extensions */,",
    )
    text = text.replace(
        "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = Runner;",
        "\t\t\tdependencies = (\n\t\t\t\tIOSVPNDEP01 /* PBXTargetDependency */,\n\t\t\t);\n\t\t\tname = Runner;",
    )
    text = text.replace(
        "\t\t\ttargets = (\n\t\t\t\t97C146ED1CF9000F007C117D /* Runner */,\n\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,\n\t\t\t);",
        "\t\t\ttargets = (\n\t\t\t\t97C146ED1CF9000F007C117D /* Runner */,\n\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,\n\t\t\t\tIOSVPNTGT01 /* VpnExtension */,\n\t\t\t);",
    )
    text = text.replace(
        "/* End PBXTargetDependency section */",
        dep + "\n/* End PBXTargetDependency section */",
    )

    # Runner sources
    text = text.replace(
        "\t\t97C146EA1CF9000F007C117D /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n",
        "\t\t97C146EA1CF9000F007C117D /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\tIOSVPNBLD01 /* VpnConstants.swift in Sources */,\n\t\t\t\tIOSVPNBLD02 /* VpnTunnelManager.swift in Sources */,\n",
    )

    # Extension build phases
    text = text.replace(
        "/* End PBXFrameworksBuildPhase section */",
        """
\t\tIOSVPNFRM01 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXFrameworksBuildPhase section */""",
    )
    text = text.replace(
        "/* End PBXResourcesBuildPhase section */",
        """
\t\tIOSVPNRES01 /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXResourcesBuildPhase section */""",
    )
    text = text.replace(
        "/* End PBXSourcesBuildPhase section */",
        """
\t\tIOSVPNSRC01 /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\tIOSVPNBLD01 /* VpnConstants.swift in Sources */,
\t\t\t\tIOSVPNBLD03 /* PacketTunnelProvider.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */""",
    )

    # Runner entitlements in build settings
    for marker in ("97C147061CF9000F007C117D /* Debug */", "97C147071CF9000F007C117D /* Release */", "249021D4217E4FDB00AE95B9 /* Profile */"):
        text = text.replace(
            f"\t\t{marker} = {{\n\t\t\tisa = XCBuildConfiguration;",
            f"\t\t{marker} = {{\n\t\t\tisa = XCBuildConfiguration;",
        )
    text = text.replace(
        "\t\t\t\tINFOPLIST_FILE = Runner/Info.plist;\n",
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n\t\t\t\tINFOPLIST_FILE = Runner/Info.plist;\n",
    )

    text = text.replace("/* End XCConfigurationList section */", ext_configs + "\n/* End XCConfigurationList section */")

    PBX.write_text(text, encoding="utf-8")
    print("✅ 已写入 VpnExtension 到 project.pbxproj")
    return 0


if __name__ == "__main__":
    sys.exit(main())
