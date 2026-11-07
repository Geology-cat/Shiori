# Shiori のビルド用ショートカット
DERIVED := build
APP := $(DERIVED)/Build/Products/Release/Shiori.app
DEBUG_APP := $(DERIVED)/Build/Products/Debug/Shiori.app

# Apple Development の証明書があれば使う。署名が安定するので、
# ビルドのたびにデスクトップなどへのアクセス許可を聞かれなくなる。なければアドホック署名。
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | awk '{print $$2}')
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := -
endif
XCODEBUILD := xcodebuild -project Shiori.xcodeproj -scheme Shiori -derivedDataPath $(DERIVED) CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" -quiet

.PHONY: web test test-web test-swift debug app run dmg clean

web:            ## ビューワー (web/dist) を作り直す
	cd web && npm install --no-audit --no-fund && node build.mjs

test: test-web test-swift   ## すべてのテスト

test-web:       ## レンダラのテスト
	cd web && node --test test/

test-swift:     ## Swift の単体テスト
	$(XCODEBUILD) -destination 'platform=macOS' test

debug:          ## デバッグビルド
	$(XCODEBUILD) -configuration Debug build

app:            ## リリースビルド
	$(XCODEBUILD) -configuration Release build

run: debug      ## デバッグビルドを起動（旧版の誤起動を避けるためパスで指定）
	open "$(DEBUG_APP)"

dmg: app        ## 配布用 DMG を作る
	./scripts/make_dmg.sh "$(APP)"

clean:
	rm -rf $(DERIVED)
