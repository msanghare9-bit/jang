"""Adapte le projet Android généré par `flutter create` aux besoins de Jàng.

Lancé à chaque construction dans GitHub Actions (le dossier android/ est régénéré).
"""
import pathlib
import re
import shutil
import sys

root = pathlib.Path(__file__).resolve().parent.parent
app = root / "android" / "app"

# 1. build.gradle(.kts) : version minimale d'Android et signature de publication.
kts = app / "build.gradle.kts"
groovy = app / "build.gradle"
if kts.exists():
    s = kts.read_text()
    s = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 23", s, count=1)
    if 'create("release")' not in s:
        signing = '''
    signingConfigs {
        create("release") {
            val ks = System.getenv("JANG_KEYSTORE_PATH")
            if (ks != null && ks.isNotEmpty()) {
                storeFile = file(ks)
                storePassword = System.getenv("JANG_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("JANG_KEY_ALIAS")
                keyPassword = System.getenv("JANG_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {'''
        s = s.replace("\n    buildTypes {", signing, 1)
        s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = if (System.getenv("JANG_KEYSTORE_PATH").isNullOrEmpty()) '
                      'signingConfigs.getByName("debug") else signingConfigs.getByName("release")', 1)
    # Syntaxe exigée par Kotlin 2.3 pour la version Java cible.
    if re.search(r"kotlinOptions\s*\{", s):
        s = re.sub(r"\n\s*kotlinOptions\s*\{[^}]*\}", "", s, count=1)
        s += "\nkotlin {\n    compilerOptions {\n        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)\n    }\n}\n"
    kts.write_text(s)
elif groovy.exists():
    s = groovy.read_text()
    s = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdkVersion 23", s, count=1)
    groovy.write_text(s)
else:
    sys.exit("build.gradle introuvable")

# 2. AndroidManifest : accès internet, nom affiché.
manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
m = manifest.read_text()
if "android.permission.INTERNET" not in m:
    m = m.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Jàng"', m, count=1)
# Moteur graphique classique (Skia) : évite l'écran blanc sur certains téléphones.
if "EnableImpeller" not in m:
    m = m.replace("</application>",
                  '    <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />\n    </application>', 1)
# Lecture à voix haute (prononciation de l'anglais) : Android 11+ doit voir le moteur de synthèse vocale.
if "TTS_SERVICE" not in m:
    tts = '<intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>'
    if "<queries>" in m:
        m = m.replace("<queries>", "<queries>\n        " + tts, 1)
    else:
        m = m.replace("</manifest>", "    <queries>" + tts + "</queries>\n</manifest>", 1)
manifest.write_text(m)

# 3. Icône de l'application.
icons = root / "tool" / "icons"
res = app / "src" / "main" / "res"
if icons.exists():
    for d in icons.iterdir():
        target = res / d.name
        target.mkdir(parents=True, exist_ok=True)
        for f in d.iterdir():
            shutil.copy(f, target / f.name)

# 4. Kotlin récent : les bibliothèques Firebase actuelles l'exigent (Flutter 3.32 fournit une version plus ancienne).
for name in ("settings.gradle.kts", "settings.gradle"):
    f = root / "android" / name
    if f.exists():
        t = f.read_text()
        t = re.sub(r'(id\(?\s*"org\.jetbrains\.kotlin\.android"\s*\)?\s*version\s*)"[^"]+"', r'\g<1>"2.3.0"', t)
        f.write_text(t)
        print(t)

print("Projet Android adapté.")
print(kts.read_text() if kts.exists() else groovy.read_text())
