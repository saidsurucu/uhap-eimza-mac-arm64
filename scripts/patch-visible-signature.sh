#!/usr/bin/env bash
# VisibleSignatureImageCreator.createImage içindeki ölü "C:\1\imza.png" yazımını
# (Files.write) kaldırır. javac/java için JDK 17+ gerekir.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR="$ROOT/build/app/Ard.ESignature.jar"
JAVASSIST="$ROOT/.jre-cache/javassist.jar"
# javac/java: sistem (17+) ya da indirilmiş Zulu 21
JBIN="$(javac -version >/dev/null 2>&1 && dirname "$(command -v javac)" || echo "$ROOT/.jre-cache/zulu21/bin")"

test -f "$JAR" || { echo "build/app/Ard.ESignature.jar yok — önce prep"; exit 1; }
if [ ! -f "$JAVASSIST" ]; then
  echo ">> javassist indiriliyor..."
  curl -fsSL -o "$JAVASSIST" \
    "https://repo1.maven.org/maven2/org/javassist/javassist/3.30.2-GA/javassist-3.30.2-GA.jar"
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/out"
cat > "$WORK/Patch.java" <<'JAVA'
import javassist.*;
import javassist.bytecode.*;

public class Patch {
  public static void main(String[] args) throws Exception {
    String jar = args[0], outDir = args[1];
    ClassPool cp = ClassPool.getDefault();
    cp.insertClassPath(jar);
    CtClass cc = cp.get("utilities.signer.pades.VisibleSignatureImageCreator");
    CtMethod m = cc.getDeclaredMethod("createImage");
    // Ölü ifade düz-akış (branch hedefi içermez) ve net stack etkisi sıfırdır:
    //   ldc "C:\1\imza.png" ... invokestatic Files.write ... pop
    // Tüm ifadeyi NOP'a çeviririz; böylece hem yazma çağrısı hem de sabit
    // referansı bytecode'dan kalkar. Metodun dönüş davranışı değişmez.
    MethodInfo mi = m.getMethodInfo();
    ConstPool pool = mi.getConstPool();
    CodeIterator it = mi.getCodeAttribute().iterator();
    int start = -1, end = -1;
    while (it.hasNext()) {
      int idx = it.next();
      int op = it.byteAt(idx);
      if (start < 0 && (op == Opcode.LDC || op == Opcode.LDC_W)) {
        int ref = (op == Opcode.LDC) ? it.byteAt(idx + 1) : it.u16bitAt(idx + 1);
        if (pool.getTag(ref) == ConstPool.CONST_String
            && pool.getStringInfo(ref).endsWith("imza.png")) {
          start = idx;
        }
      } else if (start >= 0 && op == Opcode.INVOKESTATIC) {
        int ref = it.u16bitAt(idx + 1);
        if ("java.nio.file.Files".equals(pool.getMethodrefClassName(ref))
            && "write".equals(pool.getMethodrefName(ref))) {
          int after = it.next();  // dönen Path değerini atan pop
          if (it.byteAt(after) != Opcode.POP)
            throw new IllegalStateException(
                "Files.write sonrasi pop bekleniyordu, opcode=" + it.byteAt(after));
          end = after;
          break;
        }
      }
    }
    if (start < 0 || end < 0)
      throw new IllegalStateException(
          "imza.png Files.write ifadesi bulunamadi (start=" + start + ", end=" + end + ")");
    for (int i = start; i <= end; i++) it.writeByte(Opcode.NOP, i);
    cc.writeFile(outDir);   // outDir/utilities/signer/pades/VisibleSignatureImageCreator.class
    System.out.println("patched (NOP " + start + ".." + end + ")");
  }
}
JAVA

"$JBIN/javac" -cp "$JAVASSIST" -d "$WORK/out" "$WORK/Patch.java"
"$JBIN/java"  -cp "$WORK/out:$JAVASSIST" Patch "$JAR" "$WORK/classes"
# yamalı .class'ı jar'a geri yaz
( cd "$WORK/classes" && zip -q "$JAR" utilities/signer/pades/VisibleSignatureImageCreator.class )
echo ">> visible-signature yaması uygulandı"
