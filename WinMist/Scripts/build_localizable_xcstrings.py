#!/usr/bin/env python3
# Generates Localizable.xcstrings from Swift String(localized:) keys + translation table.
# Run from repo: python3 Scripts/build_localizable_xcstrings.py

from __future__ import annotations

import json
import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[1] / "Wist"
LOCALES = ["es", "zh-Hans", "hi", "ar", "fr", "he"]


def load_l10n_bundle() -> dict[str, dict[str, str]]:
    """Machine translations from Scripts/build_bundle_translatepy.py → l10n_bundle.json."""
    p = SCRIPT_DIR / "l10n_bundle.json"
    if not p.exists():
        return {}
    data = json.loads(p.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def unswift_string(raw: str) -> str:
    """Match Swift escape rules used in Scripts/build_bundle_translatepy.py."""
    out: list[str] = []
    i = 0
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw):
            n = raw[i + 1]
            if n == "n":
                out.append("\n")
                i += 2
                continue
            if n == "t":
                out.append("\t")
                i += 2
                continue
            if n == "\\":
                out.append("\\")
                i += 2
                continue
            if n == '"':
                out.append('"')
                i += 2
                continue
        out.append(raw[i])
        i += 1
    return "".join(out)

# Manual UI translations (English key -> locale -> text). Missing entries fall back to English.
T: dict[str, dict[str, str]] = {
    "Download ISO": {
        "es": "Descargar ISO",
        "zh-Hans": "下载 ISO",
        "hi": "ISO डाउनलोड करें",
        "ar": "تنزيل ISO",
        "fr": "Télécharger l’ISO",
        "he": "הורדת ISO",
    },
    "Downloads": {
        "es": "Descargas",
        "zh-Hans": "下载内容",
        "hi": "डाउनलोड",
        "ar": "التنزيلات",
        "fr": "Téléchargements",
        "he": "הורדות",
    },
    "Create USB": {
        "es": "Crear USB",
        "zh-Hans": "创建 USB",
        "hi": "USB बनाएँ",
        "ar": "إنشاء USB",
        "fr": "Créer une clé USB",
        "he": "יצירת USB",
    },
    "UUP & image": {
        "es": "UUP e imagen",
        "zh-Hans": "UUP 与映像",
        "hi": "UUP और इमेज",
        "ar": "UUP والصورة",
        "fr": "UUP et image",
        "he": "UUP ותמונה",
    },
    "Cache & ISO": {
        "es": "Caché e ISO",
        "zh-Hans": "缓存与 ISO",
        "hi": "कैश और ISO",
        "ar": "ذاكرة التخزين المؤقت وISO",
        "fr": "Cache et ISO",
        "he": "מטמון ו־ISO",
    },
    "USB imaging": {
        "es": "Grabación USB",
        "zh-Hans": "USB 写入",
        "hi": "USB इमेजिंग",
        "ar": "كتابة USB",
        "fr": "Écriture USB",
        "he": "צריבת USB",
    },
    "Workflow": {
        "es": "Flujo de trabajo",
        "zh-Hans": "工作流",
        "hi": "कार्यप्रवाह",
        "ar": "سير العمل",
        "fr": "Flux de travail",
        "he": "זרימת עבודה",
    },
    "Source": {
        "es": "Origen",
        "zh-Hans": "来源",
        "hi": "स्रोत",
        "ar": "المصدر",
        "fr": "Source",
        "he": "מקור",
    },
    "Media": {
        "es": "Medio",
        "zh-Hans": "介质",
        "hi": "मीडिया",
        "ar": "الوسيط",
        "fr": "Support",
        "he": "מדיה",
    },
    "Windows on Mac": {
        "es": "Windows en Mac",
        "zh-Hans": "Mac 上的 Windows",
        "hi": "Mac पर Windows",
        "ar": "ويندوز على ماك",
        "fr": "Windows sur Mac",
        "he": "Windows על Mac",
    },
    "Run all": {
        "es": "Ejecutar todo",
        "zh-Hans": "全部运行",
        "hi": "सब चलाएँ",
        "ar": "تشغيل الكل",
        "fr": "Tout exécuter",
        "he": "הרץ הכול",
    },
    "Cancel": {
        "es": "Cancelar",
        "zh-Hans": "取消",
        "hi": "रद्द करें",
        "ar": "إلغاء",
        "fr": "Annuler",
        "he": "ביטול",
    },
    "Stop": {
        "es": "Detener",
        "zh-Hans": "停止",
        "hi": "रोकें",
        "ar": "إيقاف",
        "fr": "Arrêter",
        "he": "עצור",
    },
    "Delete": {
        "es": "Eliminar",
        "zh-Hans": "删除",
        "hi": "हटाएँ",
        "ar": "حذف",
        "fr": "Supprimer",
        "he": "מחק",
    },
    "Finder": {
        "es": "Finder",
        "zh-Hans": "访达",
        "hi": "Finder",
        "ar": "Finder",
        "fr": "Finder",
        "he": "Finder",
    },
    "Section": {
        "es": "Sección",
        "zh-Hans": "分区",
        "hi": "खंड",
        "ar": "قسم",
        "fr": "Section",
        "he": "מקטע",
    },
    "Build": {
        "es": "Compilación",
        "zh-Hans": "版本",
        "hi": "बिल्ड",
        "ar": "البنية",
        "fr": "Build",
        "he": "בנייה",
    },
    "Filters": {
        "es": "Filtros",
        "zh-Hans": "筛选",
        "hi": "फ़िल्टर",
        "ar": "عوامل التصفية",
        "fr": "Filtres",
        "he": "מסננים",
    },
    "Product": {
        "es": "Producto",
        "zh-Hans": "产品",
        "hi": "उत्पाद",
        "ar": "المنتج",
        "fr": "Produit",
        "he": "מוצר",
    },
    "Channel": {
        "es": "Canal",
        "zh-Hans": "渠道",
        "hi": "चैनल",
        "ar": "القناة",
        "fr": "Canal",
        "he": "ערוץ",
    },
    "Architecture": {
        "es": "Arquitectura",
        "zh-Hans": "体系结构",
        "hi": "आर्किटेक्चर",
        "ar": "البنية",
        "fr": "Architecture",
        "he": "ארכיטקטורה",
    },
    "Reset": {
        "es": "Restablecer",
        "zh-Hans": "重置",
        "hi": "रीसेट",
        "ar": "إعادة تعيين",
        "fr": "Réinitialiser",
        "he": "איפוס",
    },
    "Refresh list": {
        "es": "Actualizar lista",
        "zh-Hans": "刷新列表",
        "hi": "सूची रीफ़्रेश करें",
        "ar": "تحديث القائمة",
        "fr": "Actualiser la liste",
        "he": "רענן רשימה",
    },
    "Languages & editions": {
        "es": "Idiomas y ediciones",
        "zh-Hans": "语言与版本",
        "hi": "भाषाएँ और संस्करण",
        "ar": "اللغات والإصدارات",
        "fr": "Langues et éditions",
        "he": "שפות ומהדורות",
    },
    "Language": {
        "es": "Idioma",
        "zh-Hans": "语言",
        "hi": "भाषा",
        "ar": "اللغة",
        "fr": "Langue",
        "he": "שפה",
    },
    "Edition": {
        "es": "Edición",
        "zh-Hans": "版本",
        "hi": "संस्करण",
        "ar": "الإصدار",
        "fr": "Édition",
        "he": "מהדורה",
    },
    "Cache": {
        "es": "Caché",
        "zh-Hans": "缓存",
        "hi": "कैश",
        "ar": "ذاكرة التخزين المؤقت",
        "fr": "Cache",
        "he": "מטמון",
    },
    "Log": {
        "es": "Registro",
        "zh-Hans": "日志",
        "hi": "लॉग",
        "ar": "السجل",
        "fr": "Journal",
        "he": "יומן",
    },
    "Copied": {
        "es": "Copiado",
        "zh-Hans": "已复制",
        "hi": "कॉपी किया गया",
        "ar": "تم النسخ",
        "fr": "Copié",
        "he": "הועתק",
    },
    "Progress": {
        "es": "Progreso",
        "zh-Hans": "进度",
        "hi": "प्रगति",
        "ar": "التقدم",
        "fr": "Progression",
        "he": "התקדמות",
    },
    "In progress": {
        "es": "En curso",
        "zh-Hans": "进行中",
        "hi": "प्रगति पर",
        "ar": "قيد التنفيذ",
        "fr": "En cours",
        "he": "בתהליך",
    },
    "Downloading…": {
        "es": "Descargando…",
        "zh-Hans": "正在下载…",
        "hi": "डाउनलोड हो रहा है…",
        "ar": "جارٍ التنزيل…",
        "fr": "Téléchargement…",
        "he": "מוריד…",
    },
    "Status": {
        "es": "Estado",
        "zh-Hans": "状态",
        "hi": "स्थिति",
        "ar": "الحالة",
        "fr": "État",
        "he": "מצב",
    },
    "Size": {
        "es": "Tamaño",
        "zh-Hans": "大小",
        "hi": "आकार",
        "ar": "الحجم",
        "fr": "Taille",
        "he": "גודל",
    },
    "Actions": {
        "es": "Acciones",
        "zh-Hans": "操作",
        "hi": "कार्रवाइयाँ",
        "ar": "إجراءات",
        "fr": "Actions",
        "he": "פעולות",
    },
    "All products": {
        "es": "Todos los productos",
        "zh-Hans": "所有产品",
        "hi": "सभी उत्पाद",
        "ar": "كل المنتجات",
        "fr": "Tous les produits",
        "he": "כל המוצרים",
    },
    "All channels": {
        "es": "Todos los canales",
        "zh-Hans": "所有渠道",
        "hi": "सभी चैनल",
        "ar": "كل القنوات",
        "fr": "Tous les canaux",
        "he": "כל הערוצים",
    },
    "Any": {
        "es": "Cualquiera",
        "zh-Hans": "任意",
        "hi": "कोई भी",
        "ar": "أي",
        "fr": "Toutes",
        "he": "כל",
    },
    "Stable (Retail)": {
        "es": "Estable (Retail)",
        "zh-Hans": "稳定版（零售）",
        "hi": "स्थिर (Retail)",
        "ar": "مستقر (تجزئة)",
        "fr": "Stable (Retail)",
        "he": "יציב (קמעונאי)",
    },
    "No internet connection.": {
        "es": "Sin conexión a Internet.",
        "zh-Hans": "无互联网连接。",
        "hi": "इंटरनेट कनेक्शन नहीं है।",
        "ar": "لا يوجد اتصال بالإنترنت.",
        "fr": "Pas de connexion Internet.",
        "he": "אין חיבור לאינטרנט.",
    },
    "Done.": {
        "es": "Listo.",
        "zh-Hans": "完成。",
        "hi": "हो गया।",
        "ar": "تم.",
        "fr": "Terminé.",
        "he": "בוצע.",
    },
    "Write": {
        "es": "Grabar",
        "zh-Hans": "写入",
        "hi": "लिखें",
        "ar": "كتابة",
        "fr": "Écrire",
        "he": "כתיבה",
    },
    "ISO image": {
        "es": "Imagen ISO",
        "zh-Hans": "ISO 映像",
        "hi": "ISO इमेज",
        "ar": "صورة ISO",
        "fr": "Image ISO",
        "he": "תמונת ISO",
    },
    "USB drives": {
        "es": "Unidades USB",
        "zh-Hans": "USB 驱动器",
        "hi": "USB ड्राइव",
        "ar": "محركات USB",
        "fr": "Lecteurs USB",
        "he": "כונני USB",
    },
    "Erase and write?": {
        "es": "¿Borrar y grabar?",
        "zh-Hans": "抹掉并写入？",
        "hi": "मिटाकर लिखें?",
        "ar": "مسح والكتابة؟",
        "fr": "Effacer et écrire ?",
        "he": "למחוק ולצרוב?",
    },
    "Erase and write": {
        "es": "Borrar y grabar",
        "zh-Hans": "抹掉并写入",
        "hi": "मिटाकर लिखें",
        "ar": "مسح والكتابة",
        "fr": "Effacer et écrire",
        "he": "מחק וצרוב",
    },
    "Download image": {
        "es": "Descargar imagen",
        "zh-Hans": "下载映像",
        "hi": "इमेज डाउनलोड करें",
        "ar": "تنزيل الصورة",
        "fr": "Télécharger l’image",
        "he": "הורדת תמונה",
    },
    "Select a build": {
        "es": "Seleccione una compilación",
        "zh-Hans": "选择版本",
        "hi": "एक बिल्ड चुनें",
        "ar": "اختر نسخة",
        "fr": "Sélectionnez une build",
        "he": "בחר בנייה",
    },
    "Build ISO": {
        "es": "Crear ISO",
        "zh-Hans": "生成 ISO",
        "hi": "ISO बनाएँ",
        "ar": "إنشاء ISO",
        "fr": "Créer l’ISO",
        "he": "בניית ISO",
    },
    "Error: %@": {
        "es": "Error: %@",
        "zh-Hans": "错误：%@",
        "hi": "त्रुटि: %@",
        "ar": "خطأ: %@",
        "fr": "Erreur : %@",
        "he": "שגיאה: %@",
    },
    "Choose a build on Source, select USB on Media, then Run all.": {
        "es": "Elija una compilación en Origen, seleccione USB en Medio y pulse Ejecutar todo.",
        "zh-Hans": "在“来源”选择版本，在“介质”选择 USB，然后点“全部运行”。",
        "hi": "स्रोत पर बिल्ड चुनें, मीडिया पर USB चुनें, फिर सब चलाएँ।",
        "ar": "اختر نسخة في المصدر، وUSB في الوسيط، ثم شغّل الكل.",
        "fr": "Choisissez une build dans Source, l’USB dans Support, puis Tout exécuter.",
        "he": "בחר בנייה ב״מקור״, USB ב״מדיה״, ואז ״הרץ הכול״.",
    },
    "Pipeline: downloading UUP…": {
        "es": "Canal: descargando UUP…",
        "zh-Hans": "流程：正在下载 UUP…",
        "hi": "पाइपलाइन: UUP डाउनलोड…",
        "ar": "السلسلة: تنزيل UUP…",
        "fr": "Chaîne : téléchargement UUP…",
        "he": "צינור: מוריד UUP…",
    },
    "Pipeline: building ISO…": {
        "es": "Canal: creando ISO…",
        "zh-Hans": "流程：正在生成 ISO…",
        "hi": "पाइपलाइन: ISO बन रहा है…",
        "ar": "السلسلة: إنشاء ISO…",
        "fr": "Chaîne : création de l’ISO…",
        "he": "צינור: בונה ISO…",
    },
    "Writing to USB…": {
        "es": "Grabando en USB…",
        "zh-Hans": "正在写入 USB…",
        "hi": "USB पर लिखा जा रहा है…",
        "ar": "جارٍ الكتابة على USB…",
        "fr": "Écriture sur USB…",
        "he": "כותב ל־USB…",
    },
    "Downloading UUP…": {
        "es": "Descargando UUP…",
        "zh-Hans": "正在下载 UUP…",
        "hi": "UUP डाउनलोड…",
        "ar": "جارٍ تنزيل UUP…",
        "fr": "Téléchargement UUP…",
        "he": "מוריד UUP…",
    },
    "Building ISO…": {
        "es": "Creando ISO…",
        "zh-Hans": "正在生成 ISO…",
        "hi": "ISO बन रहा है…",
        "ar": "جارٍ إنشاء ISO…",
        "fr": "Création de l’ISO…",
        "he": "בונה ISO…",
    },
}


def extract_keys(swift_root: Path) -> list[str]:
    keys: list[str] = []
    seen: set[str] = set()
    pattern1 = re.compile(r'String\(localized:\s*"((?:\\.|[^"\\])*)"\s*\)')
    pattern_fmt = re.compile(
        r'String\(format:\s*String\(localized:\s*"((?:\\.|[^"\\])*)"\)'
    )
    for path in sorted(swift_root.rglob("*.swift")):
        if "ThirdParty" in str(path):
            continue
        text = path.read_text(encoding="utf-8")
        for r in (pattern1, pattern_fmt):
            for m in r.finditer(text):
                s = unswift_string(m.group(1))
                if s not in seen:
                    seen.add(s)
                    keys.append(s)
    return keys


def build_catalog(keys: list[str], bundle: dict[str, dict[str, str]]) -> dict:
    strings: dict = {}
    for key in keys:
        locs: dict = {
            "en": {"stringUnit": {"state": "translated", "value": key}},
        }
        machine = bundle.get(key) or {}
        manual = T.get(key) or {}
        row = {**machine, **manual}
        for loc in LOCALES:
            val = row.get(loc, key)
            if val is None or (isinstance(val, str) and not val.strip()):
                val = key
            locs[loc] = {"stringUnit": {"state": "translated", "value": val}}
        strings[key] = {"localizations": locs}
    return {
        "sourceLanguage": "en",
        "strings": strings,
        "version": "1.0",
    }


def main() -> None:
    keys = extract_keys(ROOT)
    bundle = load_l10n_bundle()
    catalog = build_catalog(keys, bundle)
    out = ROOT / "Localizable.xcstrings"
    out.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {out} with {len(keys)} keys.")


if __name__ == "__main__":
    main()
