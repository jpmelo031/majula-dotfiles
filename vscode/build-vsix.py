#!/usr/bin/env python3
"""Packs an extension folder into a .vsix that `code --install-extension` accepts.

Usage: build-vsix.py <extension-dir> <output.vsix>
A .vsix is a zip with the extension under extension/ plus two small manifests,
so no Node.js or vsce is needed for a theme.
"""
import json
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

src, out = Path(sys.argv[1]), Path(sys.argv[2])
pkg = json.loads((src / "package.json").read_text())

content_types = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
"""

manifest = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="{escape(pkg["name"])}" Version="{escape(pkg["version"])}" Publisher="{escape(pkg["publisher"])}"/>
    <DisplayName>{escape(pkg["displayName"])}</DisplayName>
    <Description xml:space="preserve">{escape(pkg["description"])}</Description>
    <Categories>Themes</Categories>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="{escape(pkg["engines"]["vscode"])}"/>
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
"""

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as vsix:
    vsix.writestr("[Content_Types].xml", content_types)
    vsix.writestr("extension.vsixmanifest", manifest)
    for path in sorted(p for p in src.rglob("*") if p.is_file()):
        vsix.write(path, "extension/" + path.relative_to(src).as_posix())
