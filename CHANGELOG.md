# Changelog

## [3.5.0](https://github.com/misty-step/thinktank/compare/v3.4.0...v3.5.0) (2026-02-25)


### Features

* add retry/backoff for transient model failures ([#223](https://github.com/misty-step/thinktank/issues/223)) ([df2ced4](https://github.com/misty-step/thinktank/commit/df2ced4863747947119fb2b22b876a419b483da0))

## [3.4.0](https://github.com/misty-step/thinktank/compare/v3.3.0...v3.4.0) (2026-02-23)


### Features

* **models:** add 14 SOTA models; update council to glm-5, minimax-m2.5 ([684bed3](https://github.com/misty-step/thinktank/commit/684bed395fbcf7c935b25a108686aade7fd43813))
* **models:** add claude-opus-4-6, claude-sonnet-4-6, gemini-3.1-pro; update council defaults ([edf3f42](https://github.com/misty-step/thinktank/commit/edf3f4215bddcde42cb2f369cf69b5270eafed27))
* **models:** add claude-opus-4-6, claude-sonnet-4-6, gemini-3.1-pro; update council defaults ([d7d61b9](https://github.com/misty-step/thinktank/commit/d7d61b9f3fb130d33e77d432be856a42dbd2ddff))


### Bug Fixes

* add CI job to satisfy branch protection check ([1a5059e](https://github.com/misty-step/thinktank/commit/1a5059e876339c3a4235d07a20ca5adc09a65c63))
* address CodeRabbit review feedback in test files ([788522f](https://github.com/misty-step/thinktank/commit/788522f594c94362f27e00373cf01e87f7958316))
* **ci:** cerberus@v2 — switch kimi-api-key to api-key with OPENROUTER_API_KEY ([3fa1f6f](https://github.com/misty-step/thinktank/commit/3fa1f6f992b149552030fbd58df5e73280a5bd00))
* resolve TestProviderRateLimiter_ConcurrentAccess deadlock ([#210](https://github.com/misty-step/thinktank/issues/210)) ([ce3e408](https://github.com/misty-step/thinktank/commit/ce3e408c240fbbfdfb10e16f36bbe22180db88d3))
* **tests:** update hardcoded model counts from 21→39 (17→35 production) after SOTA expansion ([4ae5e07](https://github.com/misty-step/thinktank/commit/4ae5e07a20473e0a99dfdff9076056d7f21d293e))
* **tests:** update select_models_test.go council refs to current-gen models ([b56fc10](https://github.com/misty-step/thinktank/commit/b56fc108c2a1b7ac31436a47d1687763207afb5d))
* **test:** update model count from 21 to 39 after SOTA roster expansion ([be31ccf](https://github.com/misty-step/thinktank/commit/be31ccf4f6543f4af6abaddb0e9805fb3d6d1e13))
* update default synthesis model from gemini-3-pro to gemini-3.1-pro ([0660888](https://github.com/misty-step/thinktank/commit/066088826cdacc38516fcd053428c0688237fe88))

## [3.3.0](https://github.com/misty-step/thinktank/compare/v3.2.0...v3.3.0) (2026-02-06)


### Features

* **ux:** add loading indicator during context gathering phase ([#132](https://github.com/misty-step/thinktank/issues/132)) ([#195](https://github.com/misty-step/thinktank/issues/195)) ([606cf0f](https://github.com/misty-step/thinktank/commit/606cf0fa414a148e47aa690f544484fb828aae1c))

## [3.2.0](https://github.com/misty-step/thinktank/compare/v3.1.1...v3.2.0) (2026-02-06)


### Features

* add observability infrastructure (metrics collection) ([#141](https://github.com/misty-step/thinktank/issues/141)) ([#194](https://github.com/misty-step/thinktank/issues/194)) ([ce8b883](https://github.com/misty-step/thinktank/commit/ce8b883a74fe2f7f3f35d16432bf02404b6c81b4))

## [3.1.1](https://github.com/misty-step/thinktank/compare/v3.1.0...v3.1.1) (2026-01-30)


### Performance Improvements

* **openrouter:** add HTTP connection pooling ([#186](https://github.com/misty-step/thinktank/issues/186)) ([d0721b9](https://github.com/misty-step/thinktank/commit/d0721b9327ba3af11a0236997b5c1d8cab9d5b9f))

## [3.1.0](https://github.com/misty-step/thinktank/compare/v3.0.0...v3.1.0) (2026-01-29)


### Features

* **cli:** add memorable output directory names ([#182](https://github.com/misty-step/thinktank/issues/182)) ([50a343b](https://github.com/misty-step/thinktank/commit/50a343b5d593c5328bba87552d2011e7a7feb253))


### Bug Fixes

* **build:** use correct Go version 1.24.2 in go.mod ([9f11c44](https://github.com/misty-step/thinktank/commit/9f11c4412b27e78c42248e5407af425586f6ba6a))

## [3.0.0](https://github.com/misty-step/thinktank/compare/v2.5.0...v3.0.0) (2026-01-28)


### ⚠ BREAKING CHANGES

* github.com/phrazzld/thinktank → github.com/misty-step/thinktank

### Features

* **tui:** upgrade terminal UI with Charmbracelet ecosystem ([#177](https://github.com/misty-step/thinktank/issues/177)) ([8a20abe](https://github.com/misty-step/thinktank/commit/8a20abe290efc46794ce9fd3cc005dc063eacda8))


### Miscellaneous Chores

* migrate repository from phrazzld to misty-step ([8f02d3d](https://github.com/misty-step/thinktank/commit/8f02d3d309a04948bffa153a4d0f48d5e41ad267))

## [2.5.0](https://github.com/phrazzld/thinktank/compare/v2.4.2...v2.5.0) (2026-01-27)


### Features

* **cli:** add model suggestions to --model flag errors ([#175](https://github.com/phrazzld/thinktank/issues/175)) ([02cd427](https://github.com/phrazzld/thinktank/commit/02cd427fca4d7b4afb36668d12b9f9a55631750c)), closes [#129](https://github.com/phrazzld/thinktank/issues/129)
* **security:** add govulncheck to CI security job ([#172](https://github.com/phrazzld/thinktank/issues/172)) ([22b7280](https://github.com/phrazzld/thinktank/commit/22b7280664fdf9d5f70d3763a0b9f96ad4a56a1d))

## [2.4.2](https://github.com/phrazzld/thinktank/compare/v2.4.1...v2.4.2) (2026-01-17)


### Bug Fixes

* **ux:** sanitize display paths to prevent absolute path leaks ([#122](https://github.com/phrazzld/thinktank/issues/122)) ([#169](https://github.com/phrazzld/thinktank/issues/169)) ([e7558a5](https://github.com/phrazzld/thinktank/commit/e7558a53d47ee02ccb521c48eb53b30a07498bff))

## [2.4.1](https://github.com/phrazzld/thinktank/compare/v2.4.0...v2.4.1) (2026-01-17)


### Bug Fixes

* **security:** add path traversal validation for file writes ([#167](https://github.com/phrazzld/thinktank/issues/167)) ([e47c87d](https://github.com/phrazzld/thinktank/commit/e47c87d4d98d6bdeb1ca25651b94a8ea2308d46e))

## [2.4.0](https://github.com/phrazzld/thinktank/compare/v2.3.0...v2.4.0) (2026-01-17)


### Features

* **fileutil:** implement concurrent file processing pipeline ([#137](https://github.com/phrazzld/thinktank/issues/137)) ([#165](https://github.com/phrazzld/thinktank/issues/165)) ([9be7631](https://github.com/phrazzld/thinktank/commit/9be76318624e47f0783540cad2b4500e43bb506e))

## [2.3.0](https://github.com/phrazzld/thinktank/compare/v2.2.0...v2.3.0) (2026-01-17)


### Features

* **ci:** add automatic PR size labeling workflow ([#163](https://github.com/phrazzld/thinktank/issues/163)) ([a2db6ee](https://github.com/phrazzld/thinktank/commit/a2db6ee924ff27c1e4a8b91a7a468896cdc8e268)), closes [#151](https://github.com/phrazzld/thinktank/issues/151)
* **security:** add gitleaks pre-commit secrets scanning ([#161](https://github.com/phrazzld/thinktank/issues/161)) ([10d05c5](https://github.com/phrazzld/thinktank/commit/10d05c523b0ef4f2acfb52e022047f0dc687528f)), closes [#152](https://github.com/phrazzld/thinktank/issues/152)

## [2.2.0](https://github.com/phrazzld/thinktank/compare/v2.1.0...v2.2.0) (2026-01-16)


### Features

* **models:** expand core council from 5 to 8 models ([638168e](https://github.com/phrazzld/thinktank/commit/638168e92173f397a87157e795881f63663f4bbb))


### Performance Improvements

* cache git repo detection to reduce subprocess overhead ([#159](https://github.com/phrazzld/thinktank/issues/159)) ([865376a](https://github.com/phrazzld/thinktank/commit/865376a3c1669c0964d170426805d037388bbaf0))

## [2.1.0](https://github.com/phrazzld/thinktank/compare/v2.0.0...v2.1.0) (2026-01-16)


### Features

* **security:** add OpenRouter API key pattern to secret detection ([#156](https://github.com/phrazzld/thinktank/issues/156)) ([79faad8](https://github.com/phrazzld/thinktank/commit/79faad8109bdd75b78eef50fb229ca75524eb8f7))

## [2.0.0](https://github.com/phrazzld/thinktank/compare/v1.0.0...v2.0.0) (2026-01-14)


### ⚠ BREAKING CHANGES

* Internal API changes; external CLI interface unchanged

### Features

* achieve 83.6% test coverage exceeding 80% CI threshold ([b9e5325](https://github.com/phrazzld/thinktank/commit/b9e53259c2aaa08900438f6f23982a2037d9bd3f))
* add 8 new model configurations with comprehensive validation ([affca3d](https://github.com/phrazzld/thinktank/commit/affca3d1f7cf1f5867c073427f1a117a5315ff29))
* add automated versioning with release-please and GoReleaser ([35f30b8](https://github.com/phrazzld/thinktank/commit/35f30b8a20954c358037eaa62e4f627f46b55033))
* add CI configuration validation to pre-commit hooks ([3ddd5d6](https://github.com/phrazzld/thinktank/commit/3ddd5d66f33ab3e2b7d13c0d4f59b3078926d70e))
* add comprehensive --help flag support to CLI ([8148441](https://github.com/phrazzld/thinktank/commit/81484415e449cf4520ac929d0e9e0a8440557c6b))
* add comprehensive edge case tests for GetModelRateLimit() function ([4bece99](https://github.com/phrazzld/thinktank/commit/4bece994551a02f64ddc17c30e6ac9503cd9f6c0))
* add comprehensive error handling tests and infrastructure ([ffe9d25](https://github.com/phrazzld/thinktank/commit/ffe9d2582da8fd1776a48834160b6713f5c519bc))
* add comprehensive integration tests for OpenAI provider entry points ([ff8fb7f](https://github.com/phrazzld/thinktank/commit/ff8fb7feba1f101e4b5c262cdc594d73bbef6d0b))
* add comprehensive load testing framework for model reliability ([9e516b5](https://github.com/phrazzld/thinktank/commit/9e516b5f23212c338e66f95b3215feb1da871a18))
* add comprehensive streaming tokenizer performance benchmarks ([d20b05d](https://github.com/phrazzld/thinktank/commit/d20b05d3d7a3cb4b56baed87f38eddf7aca3068e))
* add config option for file and directory permissions ([4963e2c](https://github.com/phrazzld/thinktank/commit/4963e2cf04a528a15ac07ca685810c164193112c))
* add context propagation to FileWriter interface for correlation ID traceability ([ae9d19e](https://github.com/phrazzld/thinktank/commit/ae9d19e393258093909f7179dedcadcbdeda2fe0))
* add core data structures for modern clean CLI output ([30be224](https://github.com/phrazzld/thinktank/commit/30be224bea8f4050be0aaa16b1ca8279d0353f41))
* add coverage-focused development targets to Makefile ([0676adc](https://github.com/phrazzld/thinktank/commit/0676adc55d0af60237587449f9198bd5faa84f59))
* add defensive cleanup for test artifacts in CLI test suite ([adc130a](https://github.com/phrazzld/thinktank/commit/adc130a2ecca7d0e5b9622e88c631e35e74cf839))
* add Docker configuration for E2E testing ([0937119](https://github.com/phrazzld/thinktank/commit/0937119b3a22400ee81a4cc6473b75f055871670))
* add GitHub issue templates for feature requests, bugs, and refactoring ([bc72841](https://github.com/phrazzld/thinktank/commit/bc72841ad1ffc72bd62dffbc7b5774ed44f2edbc))
* add golangci-lint and coverage reporting to CI ([#154](https://github.com/phrazzld/thinktank/issues/154)) ([b808e5c](https://github.com/phrazzld/thinktank/commit/b808e5c956bfe1672620d010fd964f9f7b8ca0ee))
* add grok-4 support and remove deprecated models ([9027f72](https://github.com/phrazzld/thinktank/commit/9027f7225feb8233cb44de7f5fb1ec676dc19327))
* add HTTP client mocking support for OpenRouter tests ([57ddfe3](https://github.com/phrazzld/thinktank/commit/57ddfe39644363d8fda00ecd9d1db2cf5446f33b))
* add kimi-k2 model and update max output tokens for all models ([0f6d7f5](https://github.com/phrazzld/thinktank/commit/0f6d7f52ed0cd3decef7c7df54c63f944f79e25f))
* add MockLogger in internal/testutil ([4ff2cab](https://github.com/phrazzld/thinktank/commit/4ff2cabc2ac54735bffa12cdcc0765f8ed1bef09))
* add quality dashboard system and clean repository ([a5255a8](https://github.com/phrazzld/thinktank/commit/a5255a88195e4aec0fa84b40055a3fb71ab8e4b4))
* add support for inception/mercury model ([442f33d](https://github.com/phrazzld/thinktank/commit/442f33d258eca0174aadc1f1c99bf10d103df3bd))
* add tasks for updating AuditLogger implementations (T038, T039) ([a512c17](https://github.com/phrazzld/thinktank/commit/a512c17e0f797d01e83712d993087a999b9ee559))
* add test models to resolve CI integration test failures ([7471910](https://github.com/phrazzld/thinktank/commit/7471910a34f45a84b741ca9c16266a0eea3f6136))
* add timeout CLI flag with 10-minute default ([f567183](https://github.com/phrazzld/thinktank/commit/f5671831da543cc4b1cf08c29cc947ede4345f1f))
* add vulnerability scan job skeleton to CI pipeline ([d0f2a38](https://github.com/phrazzld/thinktank/commit/d0f2a38a71224a66a8b39ccbf6c351631c73abf3))
* audit and update legacy logging in registry and fileutil packages (T023) ([720f2d5](https://github.com/phrazzld/thinktank/commit/720f2d516078ce825de8c24a1dbe0b70ebdd785a))
* change meta-llama to meta in model APIModelID fields ([1f24f85](https://github.com/phrazzld/thinktank/commit/1f24f854dbfa30e5a0178c48b29ea488bb7d46e1))
* complete automated vulnerability scanning implementation (T009-T012) ([da130be](https://github.com/phrazzld/thinktank/commit/da130be5b1ed47a7873ae31969b131b979bac368))
* complete Carmack-style function refactoring with comprehensive quality assurance ([715f567](https://github.com/phrazzld/thinktank/commit/715f567235a3cf8261eba72735f75eae391493f3))
* complete CI fixes and OpenRouter consolidation documentation ([06f1666](https://github.com/phrazzld/thinktank/commit/06f16664df2b69862450a2068ba8de00b4a6210c))
* complete CI integration and performance validation (T008) ([4dfd1d3](https://github.com/phrazzld/thinktank/commit/4dfd1d3d5617f2d11082e22fdc3759e0fda5460a))
* complete CLI output polish with perfect visual hierarchy ([12169a2](https://github.com/phrazzld/thinktank/commit/12169a238f9284c88673fbe3147e562c5e004bbd))
* complete CLI simplification infrastructure ([5815f1d](https://github.com/phrazzld/thinktank/commit/5815f1dca1a3ac94129e6658fe80b0dde3c73414))
* complete CLI simplification with token-based multi-model system ([ed681a1](https://github.com/phrazzld/thinktank/commit/ed681a1f2a6d9c9a93b678f14645e0979e57f455))
* complete ConsoleWriter error handling and edge cases (T008) ([59b17ef](https://github.com/phrazzld/thinktank/commit/59b17ef6845c1de6ccd1eadb06661f2c0f43171b))
* complete E2E compatibility testing for simplified CLI interface ([57f38eb](https://github.com/phrazzld/thinktank/commit/57f38eb125b9bb95c238df1a590bea465f18d975))
* complete logging system cleanup with comprehensive testing ([b502b88](https://github.com/phrazzld/thinktank/commit/b502b88a1e9ecb6b2a6a0c9555516360544a3f79))
* complete model selection test expectations for OpenRouter consolidation ([e85965d](https://github.com/phrazzld/thinktank/commit/e85965d6d6b7b552741988e015caf7b372929315))
* complete OpenRouter consolidation - one provider to rule them all ([bd6e547](https://github.com/phrazzld/thinktank/commit/bd6e5478ffc5a7028e002ac910898637efae0b87))
* complete OpenRouter consolidation Phase 4 - documentation and cleanup ([57b2494](https://github.com/phrazzld/thinktank/commit/57b249419741bb82ae91bce428034368b17e647d))
* complete performance testing framework migration and fix test issues ([7150533](https://github.com/phrazzld/thinktank/commit/7150533c3a9ff07948b31e15f79e5bd6f3c47a7d))
* complete Phase 9.1 OpenRouter normalized tokenization system ([187f66e](https://github.com/phrazzld/thinktank/commit/187f66e4735939ff0f6bea71e4a1d9a3df2d1899))
* complete registry elimination and replace with models package ([28ffd03](https://github.com/phrazzld/thinktank/commit/28ffd03e726d9b3939f8f1d6b82ddc80d6f777a4))
* complete T014 color scheme integration for all output methods ([66c43f8](https://github.com/phrazzld/thinktank/commit/66c43f81121f578ef7460a13726a4699f7b7d0bd))
* complete T015 edge case handling with Unicode fallback detection ([0655675](https://github.com/phrazzld/thinktank/commit/065567518e65fef41f870f32618caeb7aaebedad))
* complete vulnerability detection testing and restore security (T007) ([062142b](https://github.com/phrazzld/thinktank/commit/062142ba913593581bf7d4dc1995c469c7ec0897))
* comprehensive coverage optimization with concurrent safety validation ([5a2034a](https://github.com/phrazzld/thinktank/commit/5a2034a7d0d08bc677b005dd89637210f413fa9f))
* configure consistent CI coverage measurement strategy ([b6828a1](https://github.com/phrazzld/thinktank/commit/b6828a10fcbbde00fbd61f867eae7dc4b0fddb11))
* configure vulnerability report artifact upload with retention ([3e659b9](https://github.com/phrazzld/thinktank/commit/3e659b92a2fcb56831941675455c16d0751b4216))
* create check-defaults.sh script to compare model names (T008) ([c10a178](https://github.com/phrazzld/thinktank/commit/c10a1780da37452ecdd2a4259c0e5906502d3664))
* decompose Execute() function into focused pipeline stages ([f40feec](https://github.com/phrazzld/thinktank/commit/f40feece7919d898e93b561e70d7631bb046d1e0))
* define ConsoleWriter interface for clean console output ([73e4094](https://github.com/phrazzld/thinktank/commit/73e4094213ffe1d4a48a16c6e1e7130cb7748b0f))
* define sentinel errors for synthesis and processing failures ([6b834b0](https://github.com/phrazzld/thinktank/commit/6b834b0a0ec32c81863903f99d211dd2d2a4289a))
* enforce 90% CI coverage threshold coordinating with Issue [#46](https://github.com/phrazzld/thinktank/issues/46) ([3a74b62](https://github.com/phrazzld/thinktank/commit/3a74b62356a39c3b947aae1f39e7c5c3939ca6ed))
* enhance local development workflow (CI010) ([d2de3fa](https://github.com/phrazzld/thinktank/commit/d2de3fa83c9ee7272b84ed969c62947e5b4f7d4d))
* enhance test coverage for CLI and config packages ([1e7cb4d](https://github.com/phrazzld/thinktank/commit/1e7cb4d5e570c3b1d5e2a6932479836db76518e1))
* enhance WithCorrelationID with optional ID parameter (T009) ([9565e9c](https://github.com/phrazzld/thinktank/commit/9565e9c41608f2ffa0bf6974c0389d2d272643ba))
* fix OpenRouter consolidation test configuration and add migration docs ([8025af1](https://github.com/phrazzld/thinktank/commit/8025af121ae62493caaaa569414c294a2dbf54d7))
* fix tokenizer manager tests for OpenRouter-only architecture ([c4dac48](https://github.com/phrazzld/thinktank/commit/c4dac482b9ca78899f15ac367552f268f1056d83))
* implement accurate token counting with tiktoken-go integration ([5ef8e3f](https://github.com/phrazzld/thinktank/commit/5ef8e3f219a157f67cd744399d9e619122662804))
* implement aligned model processing display with modern clean output ([7e99a12](https://github.com/phrazzld/thinktank/commit/7e99a120f9c1fb04ba4ac42554a624b2c0481a43))
* implement automated dependency updates with intelligent auto-merge ([5e6a23e](https://github.com/phrazzld/thinktank/commit/5e6a23ece3f6ebb21d7eacdc10f6909c54a42d3a))
* implement basic summary section structure (T009) ([e7ec2e6](https://github.com/phrazzld/thinktank/commit/e7ec2e6c333439cf486e03b6d6430c3947a4e3ab))
* implement BYOK (Bring Your Own Key) support for OpenRouter models ([80cb3d7](https://github.com/phrazzld/thinktank/commit/80cb3d743cd984d19496085dd01638d04b26f1a8))
* implement CI test API key management strategy and documentation ([c488fae](https://github.com/phrazzld/thinktank/commit/c488fae74ebfd744d35b59b443033dea96996c20))
* implement clean file operations output with orchestrator interface fixes ([2b7fca7](https://github.com/phrazzld/thinktank/commit/2b7fca79b33bd0be0ebf8f8263228489a866db5f))
* implement clean modern UX for token counting compatibility display ([69cb0d6](https://github.com/phrazzld/thinktank/commit/69cb0d60e7f4ec44b1fd812a0098d4e157a98263))
* implement clean process initialization without emojis ([490bf31](https://github.com/phrazzld/thinktank/commit/490bf317ac78f9b3725d77e27992fbcebb843e00))
* implement complete error scenario handling with actionable guidance (T013) ([b9deff9](https://github.com/phrazzld/thinktank/commit/b9deff988623b460422281465d1f8b80cb535275))
* implement comprehensive CI diagnostics and debugging ([f89a6d4](https://github.com/phrazzld/thinktank/commit/f89a6d440310412b34fa95dc1acd550925318376))
* implement comprehensive configuration testing (E2E-005) ([60ea96d](https://github.com/phrazzld/thinktank/commit/60ea96dd3017727a3713c8dd999ea53ca271ddb5))
* implement comprehensive logging system cleanup with dual-output architecture ([fc2eeac](https://github.com/phrazzld/thinktank/commit/fc2eeac123c288d1973a73b6433a7044db821976))
* implement comprehensive multi-model reliability enhancements ([75e09b3](https://github.com/phrazzld/thinktank/commit/75e09b39f7358eaf45ae9814dcc222d97a6c74db))
* implement comprehensive pre-commit coverage management system ([8138c95](https://github.com/phrazzld/thinktank/commit/8138c957f5bc096502471d1d3037cbcf7a1c38cf))
* implement comprehensive quality gate system with feature flags ([00a9f55](https://github.com/phrazzld/thinktank/commit/00a9f5560ae07840e81138ce54b1e874aa475c11))
* implement comprehensive security scanning with TruffleHog and security gates ([40b0cc5](https://github.com/phrazzld/thinktank/commit/40b0cc5c43ec4400d54ab47f16acba544e6fa29f))
* implement comprehensive token counting service with accurate tokenization ([28da035](https://github.com/phrazzld/thinktank/commit/28da03582ef75b5ecfe90fed6a689a892b24196d))
* implement ConsoleWriter with environment detection ([9241f31](https://github.com/phrazzld/thinktank/commit/9241f31b729fc57563662558f5d7a1ba2fd4ccaa))
* implement contextual error integration using TDD principles ([41c8b1e](https://github.com/phrazzld/thinktank/commit/41c8b1ea96ae8e298c82d02644f7721df1ee0d29))
* implement core council default model selection ([1863b92](https://github.com/phrazzld/thinktank/commit/1863b928f0b4de8118a77926153b7e4751cd3dd4))
* implement core TokenCountingService with TDD approach ([7ecbe37](https://github.com/phrazzld/thinktank/commit/7ecbe3778e9d3d8ba28b24b28c96638d1392f327))
* implement coverage-critical test target and parallel test execution ([d4dc05e](https://github.com/phrazzld/thinktank/commit/d4dc05ee0802462bc6f71191bcfb3535aa219377))
* implement critical package coverage enforcement at 95% ([b5b0b3a](https://github.com/phrazzld/thinktank/commit/b5b0b3ae7aac7a463a9b94e236cb1b5185e90b89))
* implement environment-aware color system for modern CLI output ([a048324](https://github.com/phrazzld/thinktank/commit/a0483241b988d0f5f7ce12e20bf623d0131189a6))
* implement error detail sanitization in logutil (T022) ([922b4c7](https://github.com/phrazzld/thinktank/commit/922b4c75dad8ffabb3226f5b51c6d4c00fa02992))
* implement expected error test logger for handling expected error patterns ([3826d9e](https://github.com/phrazzld/thinktank/commit/3826d9e91393bdc053c58cdb4986e85578335cb0))
* implement explicit job dependency graph in CI workflow ([e772651](https://github.com/phrazzld/thinktank/commit/e772651ca9c097b4bf2ede52e25af507564161fc))
* implement fail-fast behavior in CI pipeline quality gates ([e9d0ef4](https://github.com/phrazzld/thinktank/commit/e9d0ef4354ed8d0558234823852ba147fa33be33))
* implement failed models section with clear error display (T011) ([abbf818](https://github.com/phrazzld/thinktank/commit/abbf818c57d2d163828ef01d0614cc8b5bc4b6b5))
* implement feature flags for quality gate control ([618845e](https://github.com/phrazzld/thinktank/commit/618845e6b04ca711c5088b8e0bac79c26f6223d9))
* implement govulncheck installation with error handling in CI ([60f69ac](https://github.com/phrazzld/thinktank/commit/60f69ac5e6bf848a85f97545e73eefbbd82e960a))
* implement human-readable file size formatting ([e0d2b79](https://github.com/phrazzld/thinktank/commit/e0d2b793c6023cc0cf9c11020b93f6e7dc0aa209))
* implement in-place status updates with right-aligned display and alphabetical ordering ([d21d7cb](https://github.com/phrazzld/thinktank/commit/d21d7cbffb43b9a947963cdba5af1385a34b861f))
* implement intelligent model selection and hardcoded synthesis model ([7bb19da](https://github.com/phrazzld/thinktank/commit/7bb19da327c2e89784cef15f4e522fcf65b09fb0))
* implement logAuditEvent helper in Orchestrator ([f54508b](https://github.com/phrazzld/thinktank/commit/f54508b18cd95302fcb959f669483fa8eb5f9bbf))
* implement main function testability pattern with comprehensive RunMain tests ([fb01853](https://github.com/phrazzld/thinktank/commit/fb01853bb26dd190771fca615e6269d8927a29ab))
* implement migration guide generation from usage patterns using TDD ([566f12a](https://github.com/phrazzld/thinktank/commit/566f12a0d06ebabd18b9cba575a131fc8b321aec))
* Implement Modern Clean CLI Output System ([c25e923](https://github.com/phrazzld/thinktank/commit/c25e923639145d531d49a05d2476003cf98bc257))
* implement output files list with human-readable sizes (T010) ([f10b3ff](https://github.com/phrazzld/thinktank/commit/f10b3ff90281e1a77ec8a2048ad5ef19c095e84d))
* implement parallel test execution strategy for CPU-bound tests ([1cb670e](https://github.com/phrazzld/thinktank/commit/1cb670ec6e42c79f865ee0d2bbb266a5df0574be))
* implement proactive license checking (CI009) ([d82d305](https://github.com/phrazzld/thinktank/commit/d82d305670067c7ee3bc69efb12bf6ae54822f84))
* implement proper log stream separation (T026) ([b931744](https://github.com/phrazzld/thinktank/commit/b931744b0055f8684d753a28f0df73efb8f61285))
* implement reasoning_effort parameter for OpenAI reasoning models ([0a6f995](https://github.com/phrazzld/thinktank/commit/0a6f99547842b5ae42b8d23b27f1868e1fa26479))
* implement responsive terminal layout system for modern CLI output ([aae4fc3](https://github.com/phrazzld/thinktank/commit/aae4fc3ad8194a143e434d28e26d839be7adec29))
* implement SimplifiedConfig struct with 100% test coverage ([2f64eb2](https://github.com/phrazzld/thinktank/commit/2f64eb2b8df4ddeaa128e72eb02000c7ef38ca8d))
* implement slog-based JSON logger (T008) ([9025f56](https://github.com/phrazzld/thinktank/commit/9025f561c391a3ffc766dfd5caa3e71297c27a46))
* implement smart model selection algorithm with caching ([4200bb8](https://github.com/phrazzld/thinktank/commit/4200bb81be3bb9f7a55a0ccd32060c52aa81baf6))
* implement token-based multi-model filtering system ([f0801f3](https://github.com/phrazzld/thinktank/commit/f0801f335987f57a1255554ecfe13111c9370bea))
* implement top-level error handling in cmd/thinktank (T021) ([4dc3f93](https://github.com/phrazzld/thinktank/commit/4dc3f93622280269fe91b02b96d40eb05263b54a))
* implement vulnerability scan execution with dual reporting ([875cfee](https://github.com/phrazzld/thinktank/commit/875cfee404a1120148286f0d0961e798d0d98142))
* improve model display names with consistent provider/model format ([b06cf01](https://github.com/phrazzld/thinktank/commit/b06cf0166af6c671e4bff54c51ca12fd29a59838))
* integrate ward hooks for Claude AI code review ([4dba00d](https://github.com/phrazzld/thinktank/commit/4dba00d5ae9bd2dc85dbd0853c371853f90e9ce9))
* **models:** add GPT-5 model family via OpenRouter ([8d71ca3](https://github.com/phrazzld/thinktank/commit/8d71ca394992913decc2953345d72ccd5fc0cfc2))
* **models:** add OpenRouter GPT-5 model family and tests ([c25487c](https://github.com/phrazzld/thinktank/commit/c25487ca640ffa096e496238176d15c3ca3c9365))
* **models:** create internal/models package structure ([da80608](https://github.com/phrazzld/thinktank/commit/da806084377f68b04d487930333e38be62882b7b))
* **models:** define comprehensive ModelInfo struct ([5c508e1](https://github.com/phrazzld/thinktank/commit/5c508e10ed5a7f44169be18a31b244d560f25767))
* **models:** implement GetAPIKeyEnvVar function ([6a8561e](https://github.com/phrazzld/thinktank/commit/6a8561e1cb8ea5ffa5708a8acef02c615edbae69))
* **models:** implement GetModelInfo function ([0d15a51](https://github.com/phrazzld/thinktank/commit/0d15a5146313b0f6efe9da53f66b14d5ebfc5561))
* **models:** implement GetProviderForModel function ([beb422f](https://github.com/phrazzld/thinktank/commit/beb422fe5f8f904ed2f130d1e0894bb45ca45570))
* **models:** implement hardcoded ModelDefinitions map ([e30527e](https://github.com/phrazzld/thinktank/commit/e30527e3e44befe3268d39b87dbc219471b00000))
* **models:** implement IsModelSupported function ([64d8854](https://github.com/phrazzld/thinktank/commit/64d88541fe398dbb940e5e54b01e6a383b642d69))
* **models:** implement ListAllModels function ([bf3f879](https://github.com/phrazzld/thinktank/commit/bf3f879449009899c391c30cdfed831ba721a4ac))
* **models:** implement ListModelsForProvider function ([8eb197e](https://github.com/phrazzld/thinktank/commit/8eb197e24095ea600e945d6942f165fd7fa1d834))
* modify exit code logic based on tolerant mode (T028) ([da7d68d](https://github.com/phrazzld/thinktank/commit/da7d68d6167fed7d72e4f600b6a50856d0adf840))
* optimize CI pipeline and pre-commit hooks for performance ([ff4cd39](https://github.com/phrazzld/thinktank/commit/ff4cd39eaeffff0bcbf9b5834f856c0f03808af3))
* radically simplify CLI codebase by 55% ([964fb3c](https://github.com/phrazzld/thinktank/commit/964fb3c7e3181d1a6e2d0ffdf87350c78784facf))
* reduce large streaming tokenization test from 25MB to 20MB ([73968bd](https://github.com/phrazzld/thinktank/commit/73968bd3b9f5e81b6974ac42429c514e1c33a62c))
* reorganize project structure for better maintainability ([1228b74](https://github.com/phrazzld/thinktank/commit/1228b74f7fbc4252af1ab6a1474e9d7fd5083b45))
* Replace token estimation with accurate provider-specific tokenization ([bf183c1](https://github.com/phrazzld/thinktank/commit/bf183c18090681a1524ce5633d3580b528c0b412))
* restore comprehensive parameter validation ([4145849](https://github.com/phrazzld/thinktank/commit/4145849b590057508856cdf48023d21bd5d3b990))
* restore coverage threshold to 90% for quality gate enforcement ([3c6abe3](https://github.com/phrazzld/thinktank/commit/3c6abe34fb9c183fefd1430eca3e8d46eee5cbd7))
* **scripts:** configure coverage exclusion patterns for test helpers ([9581d2e](https://github.com/phrazzld/thinktank/commit/9581d2e2537ffa0aec9a14a1f839e3994d9a7f6a))
* **scripts:** create pre-submission coverage check script ([4272fe1](https://github.com/phrazzld/thinktank/commit/4272fe159bae974a549a0c9a0269772a4b4eab4e))
* **scripts:** update coverage scripts to properly report registry API coverage ([e9a8eea](https://github.com/phrazzld/thinktank/commit/e9a8eea257456bd978f3c5ec64ed1a70a9f2e713))
* select and document Rapid for property-based testing ([46664f3](https://github.com/phrazzld/thinktank/commit/46664f366d5929704834abbe90a5e60c58eaf80e))
* setup initial context and logger in cmd/thinktank (T020) ([a7b6850](https://github.com/phrazzld/thinktank/commit/a7b6850c5a32f345f2f1056787920fbe7ed9b021))
* setup local BACKLOG.md-based command suite ([da06e09](https://github.com/phrazzld/thinktank/commit/da06e094b413a07e041e8e931aa69c80c3470674))
* simplify CI/CD following Carmack philosophy ([b9fd1b3](https://github.com/phrazzld/thinktank/commit/b9fd1b37b445dfce65c92196336a1c3515c18399))
* simplify CLI output with emoji-prefixed design ([38f231b](https://github.com/phrazzld/thinktank/commit/38f231b03ef206a7d0cc8622929a6cd2df07a89f))
* support multiple target paths in CLI ([3781150](https://github.com/phrazzld/thinktank/commit/3781150eacb1480c8cc3bfa22bba7d94ef514a05))
* **testutil:** create MockRegistry implementation for testing ([9d7203f](https://github.com/phrazzld/thinktank/commit/9d7203f86298036a42291cd5651122cf986d7f9f))
* **testutil:** create shared test scenarios for registry API testing ([399eb73](https://github.com/phrazzld/thinktank/commit/399eb732322329310cf51d4e40b4cc959c73b679))
* **testutil:** create standardized test fixtures for models and responses ([b3bba2a](https://github.com/phrazzld/thinktank/commit/b3bba2a7675cc7a93612fc62cb89a18bb40de283))
* **testutil:** implement registry test helpers for T018 ([8dce677](https://github.com/phrazzld/thinktank/commit/8dce6770ef7972142c40d45fba94630e87a35a44))
* update auditlog for LoggerInterface and correlation ID (T017) ([9af7ec9](https://github.com/phrazzld/thinktank/commit/9af7ec905541b53c8e4167a8d40d98fa51e36860))
* update CLI documentation with simplified interface showcase ([4c6e43e](https://github.com/phrazzld/thinktank/commit/4c6e43ef6183e77086cb0140bab30e2a6912a4e3))
* update default model and fix dry-run console output ([80f1d08](https://github.com/phrazzld/thinktank/commit/80f1d080ca9752d94a0ad588277b81c7f2a3e6c8))
* update file I/O components for context and logging (T019) ([1d6f890](https://github.com/phrazzld/thinktank/commit/1d6f8902529af7ec13256939de54affddf0265f4))
* update leyline sync workflow and migrate backlog to GitHub issues ([20f1b11](https://github.com/phrazzld/thinktank/commit/20f1b11a4457fdfd7e697e1bc8e8fc5f23c4fdc0))
* update LoggerInterface with improved documentation (T007) ([467b80a](https://github.com/phrazzld/thinktank/commit/467b80a728d24210c7aa6a87a6137f93843c1c59))
* update mock AuditLogger implementations for context-aware interface (T038) ([24d9c00](https://github.com/phrazzld/thinktank/commit/24d9c00f4350fcda71c58969a4fc55cd899c332f))
* update performance benchmark tests for OpenRouter-only architecture ([c235ed3](https://github.com/phrazzld/thinktank/commit/c235ed30138b2f5668b77d7ab807d600c9fc2697))
* update slog logger to include correlation ID (T010) ([8d017e3](https://github.com/phrazzld/thinktank/commit/8d017e33ee3bf587cbb89e0d94499281505139cd))
* update thinktank/modelproc for context, logging, and LLMError (T015) ([626374b](https://github.com/phrazzld/thinktank/commit/626374b00b20dfb7ff0560d000b482b6e89fc732))
* update thinktank/orchestrator for context, logging, and error aggregation (T016) ([939ffc6](https://github.com/phrazzld/thinktank/commit/939ffc66c5ccecf56b7188c806f0a6b712f203a8))
* update thinktank/registry for context, logging, and LLMError (T014) ([8970e91](https://github.com/phrazzld/thinktank/commit/8970e913a9ca1afee3e35de175d1e7c9e87e3292))
* wrap root context with WithTimeout and propagate ([c36e335](https://github.com/phrazzld/thinktank/commit/c36e3352d6ab3ee23bed8659859a4975d5c1facf))


### Bug Fixes

* add error logging for terminal width detection failures ([276d12a](https://github.com/phrazzld/thinktank/commit/276d12a4b19edd06eea72e3b97c746f79cf5019c))
* add executable permissions to thinktank binary in e2e tests ([309cb98](https://github.com/phrazzld/thinktank/commit/309cb988980438dee1d14cc44c7bdf7db41e1e67))
* add missing checkout step to Go CI workflow read-config job ([93c9ba6](https://github.com/phrazzld/thinktank/commit/93c9ba66fd072fa43d5e8d12e89c5834b549b067))
* add missing checkout step to Security Gates workflow read-config job ([deb5067](https://github.com/phrazzld/thinktank/commit/deb5067e25922e2b2173223dc8872bd691a127f5))
* add missing expected error patterns in integration tests ([5fd189d](https://github.com/phrazzld/thinktank/commit/5fd189d884356c8a0837ee4fa79452ea4fe17b62))
* add missing expected error patterns to integration tests ([47e7f6e](https://github.com/phrazzld/thinktank/commit/47e7f6ed3242eef53b1f5ad15a761f935037c5b8))
* add mutex synchronization to MockAuditLogger to fix data race ([e629a17](https://github.com/phrazzld/thinktank/commit/e629a17752a1a8a20c8b8d2cb444fcaf4a1abea2))
* add mutex synchronization to MockFilesystemIO to fix data race ([5c3b283](https://github.com/phrazzld/thinktank/commit/5c3b2837c3cf64d620955a8681c9955d53a5facf))
* add mutex to BoundaryAuditLogger to prevent data race ([7f00508](https://github.com/phrazzld/thinktank/commit/7f00508963316e34f4b607226f8fea46f2f1b12a))
* add OPENROUTER_API_KEY to CI environment for test compatibility ([f05e020](https://github.com/phrazzld/thinktank/commit/f05e020fe1e1e2c8f6e586cfd6651c83e922a83b))
* add user config directory setup in E2E Docker container ([b43e0f3](https://github.com/phrazzld/thinktank/commit/b43e0f383e347ec6f8f1798770bebb3755fd40f9))
* address linting issues in logutil tests (T011) ([db5503f](https://github.com/phrazzld/thinktank/commit/db5503fa6d395db040a0cba1ef334ae3a63f0612))
* address trailing whitespace from pre-commit hooks ([10a9558](https://github.com/phrazzld/thinktank/commit/10a9558e248c5dcfa6e02885a4b013051aff863e))
* adjust coverage thresholds to realistic baseline values ([447ebc0](https://github.com/phrazzld/thinktank/commit/447ebc013dfbae06909a1b47636575b0edcb1f35))
* adjust package-specific coverage thresholds to realistic baselines ([bd87b2c](https://github.com/phrazzld/thinktank/commit/bd87b2c8f5d4fda0740eac832db9d2bae86237a3))
* align CLI test expectations with CI environment behavior ([62a8d96](https://github.com/phrazzld/thinktank/commit/62a8d963635f8be15ddc9467d89ee023a9201f95))
* apply pre-commit formatting fixes to hook improvement files ([70b226c](https://github.com/phrazzld/thinktank/commit/70b226cb9766446537be96c9a4144cec41793aac))
* boost thinktank package coverage to 76.0% ([e3c9603](https://github.com/phrazzld/thinktank/commit/e3c960389a931524c2914fb94bf5ab3710f0bff5))
* change safety margin from 20% to 10% ([009d50b](https://github.com/phrazzld/thinktank/commit/009d50b87af34be679249fd542499f3828698826))
* change safety margin from 20% to 10% ([8b96804](https://github.com/phrazzld/thinktank/commit/8b96804287f3f71f088b798041bb9fb3a8a42aee))
* **ci:** improve performance test reliability for CI environments ([185d840](https://github.com/phrazzld/thinktank/commit/185d8402d6459eed3436f84199099007cefdd8f9))
* complete OpenRouter consolidation Phase 5 - remaining test fixes ([773a38a](https://github.com/phrazzld/thinktank/commit/773a38a18ecaa39ceafa3da15a78fd9b670bdd29))
* complete T001-T004 critical blocking issues ([1e409d1](https://github.com/phrazzld/thinktank/commit/1e409d1c7113ae4e9d16093aed17a4e7a4abb527))
* correct API model IDs for Meta Llama models ([c365217](https://github.com/phrazzld/thinktank/commit/c365217937448d35048da1484d2ec2d1cc425b91))
* correct BYOK implementation and o3 reasoning_effort parameter ([840417d](https://github.com/phrazzld/thinktank/commit/840417d30953ec3821bf143b794ac5a53895b093))
* correct E2E test API call for SimplifiedConfig conversion ([12f99cf](https://github.com/phrazzld/thinktank/commit/12f99cf79eb8ac0fc2cac871a7e95377dc9a0bf3))
* correct exit codes for CI environment authentication failures ([8ea0b24](https://github.com/phrazzld/thinktank/commit/8ea0b243e386700dd1100ca14f3b9f2ba411d294))
* correct indentation in test files ([c48848d](https://github.com/phrazzld/thinktank/commit/c48848da7535ba99462604374a68064c26a177aa))
* correct instructions file setup in TestRunDryRunSuccess ([2921b91](https://github.com/phrazzld/thinktank/commit/2921b91065e4316d210bb885daa54c31dccafb93))
* correct reasoning_effort parameter type for o3 model ([e992472](https://github.com/phrazzld/thinktank/commit/e9924723bbd2c88f0c5321d466e463a333a3af2a))
* correct syntax error in CI workflow file for E2E tests ([7881927](https://github.com/phrazzld/thinktank/commit/7881927311d0eeadc99d4c3356949d5bd2def6f6))
* differentiate vulnerability findings from tool failures in CI ([032a60f](https://github.com/phrazzld/thinktank/commit/032a60f5f7205adc2bfc72bf07681c9fab277a3d))
* eliminate race condition in TestMain cleanup ([e03a384](https://github.com/phrazzld/thinktank/commit/e03a3841fe2aaa2343db66e02c0dacccbbff3ad5))
* eliminate remaining subprocess test in cmd/thinktank ([5c8a033](https://github.com/phrazzld/thinktank/commit/5c8a033412bd1fe499f82c6c3e696271313c2b50))
* eliminate unrealistic 20MB adaptive chunking performance test ([482487c](https://github.com/phrazzld/thinktank/commit/482487c3db685dc855f8506fbf902aad3881b5b8))
* ensure deterministic model ordering to resolve CI test failures ([3d08a4b](https://github.com/phrazzld/thinktank/commit/3d08a4bfc5ba181cbec29e772e26bc5c5effd1b4))
* filter test flags in ParseFlags to prevent subprocess test failures ([516ffee](https://github.com/phrazzld/thinktank/commit/516ffee51e58366900582d81d33beee0e177254b))
* handle CI environment and negative widths in logutil tests ([96c7236](https://github.com/phrazzld/thinktank/commit/96c7236ea7807793ee453ada3d03d9677775f8df))
* handle CLI help command exit code in Docker E2E tests ([3a38e59](https://github.com/phrazzld/thinktank/commit/3a38e59ac56a75471f2ede379c5a0b47e804dfe1))
* improve platform compatibility for E2E tests in CI ([4e5f0cd](https://github.com/phrazzld/thinktank/commit/4e5f0cd777603c414659ea215ae09d4db3065443))
* improve test documentation for model count expectations ([1bcd415](https://github.com/phrazzld/thinktank/commit/1bcd415e30ab01de33f5b31e538bf009e1c7e747))
* increase tokenizer memory test threshold ([#149](https://github.com/phrazzld/thinktank/issues/149)) ([#153](https://github.com/phrazzld/thinktank/issues/153)) ([a77abb7](https://github.com/phrazzld/thinktank/commit/a77abb78338de181e03bdb4104bef3c88332b236))
* isolate CLI test environment from real CI variables ([660e9fc](https://github.com/phrazzld/thinktank/commit/660e9fcfa315d76b93989761a563f35623924984))
* isolate environment variables in ConsoleWriter tests to prevent CI interference ([fbfbcf1](https://github.com/phrazzld/thinktank/commit/fbfbcf15a004db2b202e623c12fc209bd3ce8a66))
* isolate environment variables in TestConsoleWriter_EnvironmentDetection ([01eb0a0](https://github.com/phrazzld/thinktank/commit/01eb0a01713509f9fed4640306f07071da31e718))
* isolate environment variables in TestConsoleWriter_OutputModes ([c9c1377](https://github.com/phrazzld/thinktank/commit/c9c1377ff1b768794a2669d01ad176a12bc0ce0a))
* make dry run mode consistently skip API key validation ([11d9bdb](https://github.com/phrazzld/thinktank/commit/11d9bdb47d2a39764ef83587e0cc80002b8e6f3e))
* make quiet mode show errors as documented (T011) ([a21a24f](https://github.com/phrazzld/thinktank/commit/a21a24f0fa5ef882f514db9dcbbabf7b42138c1c))
* **models:** update test expectations for grok-4 model integration ([36f027c](https://github.com/phrazzld/thinktank/commit/36f027c0f23e140e59b2fcd22dcceba2d38daf9b))
* pin staticcheck version to v0.5.1 for CI stability ([d774adf](https://github.com/phrazzld/thinktank/commit/d774adf339fa345c5526b9319d1f5d964c056a4f))
* prevent CI environment variable inheritance in subprocess tests ([53aaaa5](https://github.com/phrazzld/thinktank/commit/53aaaa59195c06aae81d95ec2b942a7e0b9ce088))
* reduce adaptive chunking threshold from 25MB to 20MB for CI reliability ([4493899](https://github.com/phrazzld/thinktank/commit/4493899075ef5828ed7e48bd0c900d8d319a562a))
* remove API key prefix logging for security ([487773c](https://github.com/phrazzld/thinktank/commit/487773c6947916af954489dfa3a6c796350a5112))
* remove config/models.yaml dependency from E2E Dockerfile ([1e78c64](https://github.com/phrazzld/thinktank/commit/1e78c64684b81ed9dd8fd3c020e598502b528735))
* remove duplicate --fail flag from TruffleHog configuration ([1ffe329](https://github.com/phrazzld/thinktank/commit/1ffe329d8af3eeca26fc459c2997dc854011a5ff))
* remove duplicate FileWriter implementation and consolidate interfaces ([1cb2826](https://github.com/phrazzld/thinktank/commit/1cb2826a8a37b561dbc985888391a6afae44ad3c))
* remove excess newline between completion message and summary section ([c4503c9](https://github.com/phrazzld/thinktank/commit/c4503c9bf3965bcc92c844e475603f9af7b39910))
* remove test_output directories causing CI permission errors ([e40d240](https://github.com/phrazzld/thinktank/commit/e40d24097892f7170f2c72b59a8f87fd90a62ffa))
* repair subprocess test flag parsing in CLI tests ([80bc002](https://github.com/phrazzld/thinktank/commit/80bc002a1f2702c16ce656b77c9cfefbcb28a9d3))
* replace hardcoded output directory with temporary directory in TestRunDryRunSuccess ([e01bfb9](https://github.com/phrazzld/thinktank/commit/e01bfb98ae8414211ad4ce10fd4c9f8f5604a21d))
* resolve all golangci-lint violations blocking CI pipeline ([7fe8019](https://github.com/phrazzld/thinktank/commit/7fe8019bccba96996a0e464f8f3959dd7962a9a3))
* resolve all remaining integration test failures ([f9db8e9](https://github.com/phrazzld/thinktank/commit/f9db8e9a2c54baa5431b8d45b26d6c6022dfd3d3))
* resolve CI coverage failures by adjusting threshold and fixing brittle tests ([ff198b1](https://github.com/phrazzld/thinktank/commit/ff198b1f596acd6d9f754d058951b1726481b699))
* resolve CI coverage quality gate failures ([d015686](https://github.com/phrazzld/thinktank/commit/d015686d21fd0a83692a46bbda21caa50a19a8ea))
* resolve CI design flaw by separating CLI tests from race detection ([d1e5869](https://github.com/phrazzld/thinktank/commit/d1e58696c3d6a3b7a9a09e6aa0a3b47732d4e391))
* resolve CI test failure in audit log file creation test ([fd2f1f9](https://github.com/phrazzld/thinktank/commit/fd2f1f96312c1f9bc2e5251b3f16c1f5d0c74ffb))
* resolve CI test failure in TestStatusDisplay_FormatModelLine ([b8cd739](https://github.com/phrazzld/thinktank/commit/b8cd739f079843e7febc6de975a2a9093761a7df))
* resolve CI/CD pipeline failures in CLI integration tests ([a133426](https://github.com/phrazzld/thinktank/commit/a1334261ba81d9a224131b40f680116708c4c70e))
* resolve cross-platform binary execution in E2E tests ([9a1efc8](https://github.com/phrazzld/thinktank/commit/9a1efc8edd8ae7d9d41614614b82a991782b029c))
* resolve data race in CLI test runner ([f6457e0](https://github.com/phrazzld/thinktank/commit/f6457e052e9b806ec4747f7e57c4b71db3ea1794))
* resolve data race in MockFileWriter test implementations ([26e7128](https://github.com/phrazzld/thinktank/commit/26e7128a3a403f0d44281d9c69800ed2a35af462))
* resolve DeepSeek model concurrency conflicts in batch processing ([c437891](https://github.com/phrazzld/thinktank/commit/c43789189b46baa5bdb4f18c8168688023c4dac7))
* resolve errcheck and unused function violations in integration tests ([f4af9ab](https://github.com/phrazzld/thinktank/commit/f4af9abb0fa87819e0cb0400c67323c1f7a68ff3))
* resolve errcheck violations in test files to fix CI pipeline ([9c0c693](https://github.com/phrazzld/thinktank/commit/9c0c69359388232ddf98644718cbf064bf30f693))
* resolve git config issues and apply improved pre-commit hooks ([b4ac771](https://github.com/phrazzld/thinktank/commit/b4ac771607ce6615100980112e7db971e4d52e1c))
* resolve gosec SAST internal error with hybrid security scanning ([85b578c](https://github.com/phrazzld/thinktank/commit/85b578cb8c924a88c3080f83e2803fdb2a0f856f))
* resolve merge-blocking cache invalidation and test quality issues ([8725d64](https://github.com/phrazzld/thinktank/commit/8725d6404f29cb87138c6e5929d4729fa6713638))
* resolve streaming tokenizer performance issues and enhance pre-commit hooks ([ed52e28](https://github.com/phrazzld/thinktank/commit/ed52e28d2739e59b55557964cc66dcff9bc5383c))
* resolve T002 interface breaking changes throughout codebase (T015a) ([544cce4](https://github.com/phrazzld/thinktank/commit/544cce45875232facd7b70cc8471b926c74bf9a5))
* resolve TestBoundarySynthesisFlowNew CI failure ([7f927e6](https://github.com/phrazzld/thinktank/commit/7f927e6dfb84b612ebb22078d632642d7a49f2ad))
* resolve TestStreamingTokenizer_PerformanceEnvelope CI timeout failure ([a3d07ce](https://github.com/phrazzld/thinktank/commit/a3d07ce54cdfcf257350677aa74e0872ae22d519))
* restore e2e and integration tests functionality ([1e962bb](https://github.com/phrazzld/thinktank/commit/1e962bba8a798fa33000194b1492b0534c192ed6))
* skip provider availability test when API key not present ([c1d8cd4](https://github.com/phrazzld/thinktank/commit/c1d8cd4919cfd3272e96500b2a91cfdfc1bcf8f8))
* skip TestSelectModelsForConfig test when API key unavailable ([67d39c0](https://github.com/phrazzld/thinktank/commit/67d39c08f8669f3566b089540688c916a4106845))
* standardize test output directories to use temporary paths ([97e168c](https://github.com/phrazzld/thinktank/commit/97e168ceb3d5516962b97c4e7f254a6d200b4e78))
* update CI workflow to use 80% coverage threshold ([fa4e710](https://github.com/phrazzld/thinktank/commit/fa4e71088f1a84a5d1a1041384528761dcbd754c))
* update CLI test expectations to match modern output format ([7ba8ce1](https://github.com/phrazzld/thinktank/commit/7ba8ce120c0832fd076ab0928d75c9cfa411d522))
* update CLI validation tests for OpenRouter consolidation ([00e00ff](https://github.com/phrazzld/thinktank/commit/00e00ffeac29223cccecf592639fc6f55268ee0c))
* update console writer test expectations for modern output format ([620ebcc](https://github.com/phrazzld/thinktank/commit/620ebcca207fd12b484398c9452b48b77af803b9))
* update E2E test helpers to use simplified CLI format ([36dfa28](https://github.com/phrazzld/thinktank/commit/36dfa28465cca3d033ef73879b49a69ac39163e7))
* update function signatures to align with Go style ([c531c51](https://github.com/phrazzld/thinktank/commit/c531c51ae76eaa0e28f782631d1d343b0667f12b))
* update GetProviderImplementation interface to use providers.Provider instead of interface{} ([584e47b](https://github.com/phrazzld/thinktank/commit/584e47ba1485acdd2483fde5b3815ca60b6a8b7a))
* update Go to 1.24.11 to fix stdlib vulnerabilities ([#147](https://github.com/phrazzld/thinktank/issues/147)) ([663b140](https://github.com/phrazzld/thinktank/commit/663b1402ac8317a8fe8c18822a81eb7958e42aa8))
* update MockRegistry interface to support context-based methods (T037) ([d09201d](https://github.com/phrazzld/thinktank/commit/d09201d63b1b90af623840e335ae49875355d831))
* update model selection tests for OpenRouter consolidation ([224958a](https://github.com/phrazzld/thinktank/commit/224958a4ef3b8b287d339ced72bf6f7d061f3d1c))
* update package-specific coverage script to use 80% overall threshold ([7de80ae](https://github.com/phrazzld/thinktank/commit/7de80ae380acf2f0449b21d7f6d2964822e22391))
* update run name format tests to match 9-digit implementation (T040) ([66022d1](https://github.com/phrazzld/thinktank/commit/66022d1a797c767e39507c505c52ee3dd7fcbb2e))
* update streaming tokenizer timeout calculation for realistic CI performance ([abc8a7b](https://github.com/phrazzld/thinktank/commit/abc8a7bd104fe43fab4084934a8a1317e5c4fe92))
* update streaming tokenizer timeout calculation to realistic 0.5 MB/s ([1faea1a](https://github.com/phrazzld/thinktank/commit/1faea1a9c6953de2dcdbd3dfc71ec0e15657877a))
* update test expectations to match actual implementation behavior ([259fa7d](https://github.com/phrazzld/thinktank/commit/259fa7da9cf398f658176d0aff8761618b1fdf9b))
* update test references to use correct deepseek model names ([6390b2f](https://github.com/phrazzld/thinktank/commit/6390b2fcd970ad037f0b9ff7c3d4d3f7618eabbf))
* update TestConsoleWriter_ErrorWarningSuccessMessages for modern symbols ([13b8a21](https://github.com/phrazzld/thinktank/commit/13b8a2185ce64c640c3007d4216ad894d3231e19))
* update TestConsoleWriter_OutputFormatting expectations for modern CLI ([59dd391](https://github.com/phrazzld/thinktank/commit/59dd391541fae17cfc8af1d66b461a469604b37a))
* update TestLoadInvalidYAML to align with configuration fallback behavior ([0c39b27](https://github.com/phrazzld/thinktank/commit/0c39b2781c84348d8afa8db3364862986b64a384))
* update token limits for synthesis models to prevent truncation ([b0338ad](https://github.com/phrazzld/thinktank/commit/b0338adff7e208b313bf29abf8b9cc4600e4fed0))
* use correct path to binary in GitHub Actions ([5bd5825](https://github.com/phrazzld/thinktank/commit/5bd582587ac736c73fab1b6f16682a05dd73a4f2))
* use Unicode-safe character counting in layout separator tests ([fc63b89](https://github.com/phrazzld/thinktank/commit/fc63b89d49c6237e91dc20e44d1ea9f4d57741ab))
* validate individual path lengths instead of combined string ([ac93188](https://github.com/phrazzld/thinktank/commit/ac93188fbab33ad56d1b01918fd4f08cc1615eb4))


### Performance Improvements

* fix O(n²) string concatenation in token counting ([#117](https://github.com/phrazzld/thinktank/issues/117)) ([#146](https://github.com/phrazzld/thinktank/issues/146)) ([763b41a](https://github.com/phrazzld/thinktank/commit/763b41ab71f855ff420d6d21fa8d09d45352ebb6))
