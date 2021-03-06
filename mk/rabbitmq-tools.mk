READY_DEPS = $(foreach DEP,\
	       $(filter $(RABBITMQ_COMPONENTS),$(DEPS) $(BUILD_DEPS) $(TEST_DEPS)), \
	       $(if $(wildcard $(DEPS_DIR)/$(DEP)),$(DEP),))

.PHONY: update-erlang-mk update-rabbitmq-components.mk

update-erlang-mk: erlang-mk
	$(verbose) if test "$(DO_COMMIT)" = 'yes'; then \
		git diff --quiet -- erlang.mk \
		|| git commit -m 'Update erlang.mk' -- erlang.mk; \
	fi
	$(verbose) for repo in $(READY_DEPS:%=$(DEPS_DIR)/%); do \
		! test -f $$repo/erlang.mk \
		|| $(MAKE) -C $$repo erlang-mk; \
		if test "$(DO_COMMIT)" = 'yes'; then \
			(cd $$repo; \
			 git diff --quiet -- erlang.mk \
			 || git commit -m 'Update erlang.mk' -- erlang.mk); \
		fi; \
	done

update-rabbitmq-components-mk: rabbitmq-components-mk
	$(verbose) for repo in $(READY_DEPS:%=$(DEPS_DIR)/%); do \
		! test -f $$repo/rabbitmq-components.mk \
		|| $(MAKE) -C $$repo rabbitmq-components-mk; \
	done

update-contributor-code-of-conduct:
	$(verbose) for repo in $(READY_DEPS:%=$(DEPS_DIR)/%); do \
		cp $(DEPS_DIR)/rabbit_common/CODE_OF_CONDUCT.md $$repo/CODE_OF_CONDUCT.md; \
		cp $(DEPS_DIR)/rabbit_common/CONTRIBUTING.md $$repo/CONTRIBUTING.md; \
	done

ifdef CREDS
define replace_aws_creds
	set -e; \
	if test -f "$(CREDS)"; then \
	  key_id=$(shell travis encrypt --no-interactive \
	    "AWS_ACCESS_KEY_ID=$$(awk '/^rabbitmq-s3-access-key-id/ { print $$2; }' < "$(CREDS)")"); \
	  access_key=$(shell travis encrypt --no-interactive \
	    "AWS_SECRET_ACCESS_KEY=$$(awk '/^rabbitmq-s3-secret-access-key/ { print $$2; }' < "$(CREDS)")"); \
	  mv .travis.yml .travis.yml.orig; \
	  awk "\
	  /^  global:/ { \
	    print; \
	    print \"    - secure: $$key_id\"; \
	    print \"    - secure: $$access_key\"; \
	    next; \
	  } \
	  /- secure:/ { next; } \
	  { print; }" < .travis.yml.orig > .travis.yml; \
	  rm -f .travis.yml.orig; \
	else \
	  echo "        INFO: CREDS file missing; not setting/updating AWS credentials"; \
	fi
endef
else
define replace_aws_creds
	echo "        INFO: CREDS not set; not setting/updating AWS credentials"
endef
endif

ifeq ($(PROJECT),rabbit_common)
travis-yml:
	$(gen_verbose) $(replace_aws_creds)
else
travis-yml:
	$(gen_verbose) ! test -f .travis.yml || \
	(grep -E -- '- secure:' .travis.yml || :) > .travis.yml.creds
	$(verbose) cp -a $(DEPS_DIR)/rabbit_common/.travis.yml .travis.yml.orig
	$(verbose) awk ' \
	/^  global:/ { \
	  print; \
	  system("test -f .travis.yml.creds && cat .travis.yml.creds"); \
	  next; \
	} \
	/- secure:/ { next; } \
	{ print; } \
	' < .travis.yml.orig > .travis.yml
	$(verbose) rm -f .travis.yml.orig .travis.yml.creds
	$(verbose) set -e; \
	if test -f .travis.yml.patch; then \
		patch -p0 < .travis.yml.patch; \
		rm -f .travis.yml.orig; \
	fi
	$(verbose) $(replace_aws_creds)
ifeq ($(DO_COMMIT),yes)
	$(verbose) git diff --quiet .travis.yml \
	|| git commit -m 'Travis CI: Update config from rabbitmq-common' .travis.yml
endif
endif

update-travis-yml: travis-yml
	$(verbose) for repo in $(READY_DEPS:%=$(DEPS_DIR)/%); do \
		! test -f $$repo/rabbitmq-components.mk \
		|| $(MAKE) -C $$repo travis-yml; \
	done

ifneq ($(wildcard .git),)

.PHONY: sync-gitremote sync-gituser

sync-gitremote: $(READY_DEPS:%=$(DEPS_DIR)/%+sync-gitremote)
	@:

%+sync-gitremote:
	$(exec_verbose) cd $* && \
		git remote set-url origin \
		'$(call dep_rmq_repo,$(RABBITMQ_CURRENT_FETCH_URL),$(notdir $*))'
	$(verbose) cd $* && \
		git remote set-url --push origin \
		'$(call dep_rmq_repo,$(RABBITMQ_CURRENT_PUSH_URL),$(notdir $*))'

RMQ_GIT_GLOBAL_USER_NAME := $(shell git config --global user.name)
RMQ_GIT_GLOBAL_USER_EMAIL := $(shell git config --global user.email)
RMQ_GIT_USER_NAME := $(shell git config user.name)
RMQ_GIT_USER_EMAIL := $(shell git config user.email)

sync-gituser: $(READY_DEPS:%=$(DEPS_DIR)/%+sync-gituser)
	@:

%+sync-gituser:
ifeq ($(RMQ_GIT_USER_NAME),$(RMQ_GIT_GLOBAL_USER_NAME))
	$(exec_verbose) cd $* && git config --unset user.name || :
else
	$(exec_verbose) cd $* && git config user.name "$(RMQ_GIT_USER_NAME)"
endif
ifeq ($(RMQ_GIT_USER_EMAIL),$(RMQ_GIT_GLOBAL_USER_EMAIL))
	$(verbose) cd $* && git config --unset user.email || :
else
	$(verbose) cd $* && git config user.email "$(RMQ_GIT_USER_EMAIL)"
endif

show-branch: $(READY_DEPS:%=$(DEPS_DIR)/%+show-branch)
	$(verbose) printf '%-34s %s\n' $(PROJECT): "$$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)"

%+show-branch:
	$(verbose) printf '%-34s %s\n' $(notdir $*): "$$(cd $* && (git symbolic-ref -q --short HEAD || git describe --tags --exact-match))"

endif # ($(wildcard .git),)
