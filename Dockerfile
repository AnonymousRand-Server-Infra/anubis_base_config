# need this to pull things like `cp` into the barebones anubis image; we use busybox instead of
# alpine since it has statically-compiled binaries so we don't need to also pull dependencies
FROM busybox:musl AS busybox
FROM akubrinsky/envsubst AS envsubst

FROM ghcr.io/techarohq/anubis:latest

ARG DOCKER_ROOT_USER
USER ${DOCKER_ROOT_USER}

# install busybox's statically-compiled binaries for basic shell commands in anubis image
COPY --from=busybox /bin/busybox /bin/
# the "exec" form, i.e. a list, ensures that we don't need `sh` first to run this :3
RUN ["/bin/busybox", "--install", "-s", "/bin"]

# also install `envsubst`, which is not statically linked so it's gonna be harder
ARG CPU_ARCH
COPY --from=envsubst /usr/bin/envsubst /usr/bin/
# linker
COPY --from=envsubst /lib/ld-musl-${CPU_ARCH}.so.1 /lib/
# C library
COPY --from=envsubst /lib/libc.musl-${CPU_ARCH}.so.1 /lib/
# internationalization library, a dependency of `envsubst`
COPY --from=envsubst /usr/lib/libintl.so.8 /usr/lib/

# merge anubis configs from all configured places herr (e.g. a service's + the base)
# `COPY` doesn't work if `CONFIG_SRC_FILES` holds multiple space-separated files, so we instead
# make a temporary bind of the dockerfile's context to `/tmp_bind/` inside the container and `cp`
# this does require us to mount a large context, but this service shouldn't be restarted much
ARG ANUBIS_CONFIG_SRC_FILES
ARG ANUBIS_CONFIG_DEST_DIR
RUN --mount=type=bind,target=/tmp_bind/ \
    if [ -n "${ANUBIS_CONFIG_SRC_FILES}" ]; then \
        mkdir -p ${ANUBIS_CONFIG_DEST_DIR} \
        && cd /tmp_bind/ && cp -r ${ANUBIS_CONFIG_SRC_FILES} ${ANUBIS_CONFIG_DEST_DIR}; \
    fi

# set the right permissions for the private key inside the container: only accessible to root
# (we do this here instead of in a `pre_start` hook since we aren't bind mounting this file,
# and since `pre_start`s run their own container they cannot access the files copied to this one)
ARG ANUBIS_PRIVKEY_DEST_FILE
RUN chown ${DOCKER_ROOT_USER} ${ANUBIS_PRIVKEY_DEST_FILE}
RUN chmod 600 ${ANUBIS_PRIVKEY_DEST_FILE}

# custom entrypoint that runs `envsubst` on config files
# we do that in entrypoint instead of in `pre_start` for the same reason as perms changing above,
# but we also can't do it in this dockerfile since dockerfile doesn't get `env_file`'s env vars
ARG PATH_FROM_ROOT_TO_ANUBIS
RUN mkdir -p /tmp_entry/
COPY ${PATH_FROM_ROOT_TO_ANUBIS}/entrypoint.sh /tmp_entry/entrypoint.sh
RUN chmod +x /tmp_entry/entrypoint.sh
# the original entrypoint for anubis' docker image is `/ko-app/anubis`, found using:
# `docker inspect --format='{{json .Config.Entrypoint}} ghcr.io/techarohq/anubis:latest` (SYNC);
# this is needed to make sure original entrypoint still runs after ours!
# also the "exec" form, i.e. a list, ensures `command:` in compose.yaml still appends args to this
ENTRYPOINT ["/tmp_entry/entrypoint.sh", "/ko-app/anubis"]
