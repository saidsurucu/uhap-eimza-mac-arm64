SHELL := /bin/bash
ROOT := $(shell pwd)
CACHE := $(ROOT)/.jre-cache
BUILD := $(ROOT)/build
APPNAME := UHAPImza
DISPLAYNAME := UHAP İmzalama

ZULU11_URL := https://cdn.azul.com/zulu/bin/zulu11.88.17-ca-jdk11.0.31-macosx_aarch64.tar.gz
ZULU21_URL := https://cdn.azul.com/zulu/bin/zulu21.50.19-ca-jdk21.0.11-macosx_aarch64.tar.gz

RUNTIME := $(CACHE)/zulu11-runtime
# Sistem jpackage (Java 17+) varsa onu kullan, yoksa indirilmiş Zulu 21'i
JPACKAGE := $(shell command -v jpackage 2>/dev/null || echo $(CACHE)/zulu21/bin/jpackage)

.PHONY: jre
jre: $(RUNTIME)/bin/java $(JPACKAGE)

$(RUNTIME)/bin/java:
	@mkdir -p $(CACHE)
	@echo ">> Zulu 11 arm64 runtime indiriliyor..."
	@curl -fsSL "$(ZULU11_URL)" -o $(CACHE)/zulu11.tar.gz
	@rm -rf $(CACHE)/zulu11-runtime $(CACHE)/_z11 && mkdir -p $(CACHE)/_z11
	@tar -xzf $(CACHE)/zulu11.tar.gz -C $(CACHE)/_z11 --strip-components=1
	@# .app içindeki Contents/Home gerçek JDK kökü
	@if [ -d "$(CACHE)/_z11/zulu-11.jdk/Contents/Home" ]; then \
	   mv "$(CACHE)/_z11/zulu-11.jdk/Contents/Home" $(RUNTIME); \
	 elif [ -d "$(CACHE)/_z11/Contents/Home" ]; then \
	   mv "$(CACHE)/_z11/Contents/Home" $(RUNTIME); \
	 else mv $(CACHE)/_z11 $(RUNTIME); fi
	@rm -rf $(CACHE)/_z11 $(CACHE)/zulu11.tar.gz
	@echo ">> runtime: $(RUNTIME)"

$(CACHE)/zulu21/bin/jpackage:
	@if command -v jpackage >/dev/null 2>&1; then \
	   echo ">> sistem jpackage kullanılacak: $$(command -v jpackage)"; \
	 else \
	   echo ">> Zulu 21 (jpackage) indiriliyor..."; \
	   mkdir -p $(CACHE); \
	   curl -fsSL "$(ZULU21_URL)" -o $(CACHE)/zulu21.tar.gz; \
	   rm -rf $(CACHE)/zulu21 $(CACHE)/_z21 && mkdir -p $(CACHE)/_z21; \
	   tar -xzf $(CACHE)/zulu21.tar.gz -C $(CACHE)/_z21 --strip-components=1; \
	   if [ -d "$(CACHE)/_z21/zulu-21.jdk/Contents/Home" ]; then \
	     mv "$(CACHE)/_z21/zulu-21.jdk/Contents/Home" $(CACHE)/zulu21; \
	   elif [ -d "$(CACHE)/_z21/Contents/Home" ]; then \
	     mv "$(CACHE)/_z21/Contents/Home" $(CACHE)/zulu21; \
	   else mv $(CACHE)/_z21 $(CACHE)/zulu21; fi; \
	   rm -rf $(CACHE)/_z21 $(CACHE)/zulu21.tar.gz; \
	 fi

.PHONY: prep app
prep:
	@./scripts/prep-payload.sh

app: jre prep
	@RUNTIME="$(RUNTIME)" JPACKAGE="$(JPACKAGE)" ./scripts/build-app.sh

.PHONY: dmg run install clean
dmg: app
	@rm -f $(BUILD)/$(APPNAME).dmg
	@rm -rf $(BUILD)/dmgroot && mkdir -p $(BUILD)/dmgroot
	@cp -R $(BUILD)/$(APPNAME).app $(BUILD)/dmgroot/
	@ln -s /Applications $(BUILD)/dmgroot/Applications
	@hdiutil create -volname "$(APPNAME)" -srcfolder $(BUILD)/dmgroot \
	   -ov -format UDZO $(BUILD)/$(APPNAME).dmg
	@rm -rf $(BUILD)/dmgroot
	@echo ">> dmg: $(BUILD)/$(APPNAME).dmg"

run: app
	@open $(BUILD)/$(APPNAME).app

install: app
	@rm -rf "/Applications/$(APPNAME).app"
	@cp -R $(BUILD)/$(APPNAME).app /Applications/
	@echo ">> kuruldu: /Applications/$(APPNAME).app"

clean:
	@rm -rf $(BUILD)
	@echo ">> temizlendi (build/). .jre-cache korunur."
