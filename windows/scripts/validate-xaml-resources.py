"""Catch duplicate resource keys that WPF compilation may leave until startup."""
from pathlib import Path
import xml.etree.ElementTree as ET

XAML = "{http://schemas.microsoft.com/winfx/2006/xaml}"
root_dir = Path(__file__).resolve().parents[1] / "TransTools"
count = 0
for path in root_dir.rglob("*.xaml"):
    if any(part in {"bin", "obj"} for part in path.relative_to(root_dir).parts):
        continue
    root = ET.parse(path).getroot()
    for resources in root.iter():
        if not (resources.tag.endswith(".Resources") or resources.tag.endswith("ResourceDictionary")):
            continue
        seen = set()
        for item in resources:
            key = item.get(XAML + "Key")
            if key is None and item.tag.endswith("Style"):
                key = item.get("TargetType")
            if key is None and item.tag.endswith("DataTemplate") and item.get("DataType"):
                key = "DataTemplate:" + item.get("DataType")
            if key is None:
                continue
            if key in seen:
                raise ValueError(f"{path}: duplicate resource key {key}")
            seen.add(key)
            count += 1
print(f"PASS: parsed source XAML, {count} resource keys unique within their dictionaries")
