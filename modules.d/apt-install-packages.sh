if [ ! -z "${APT_INSTALL_PACKAGES}" ];
then
    log_i "Installing packages <${APT_INSTALL_PACKAGES}>"
    DEBIAN_FRONTEND=noninteractive apt install --yes ${APT_INSTALL_PACKAGES}
else
    log_i "No additional packages to install"
fi
