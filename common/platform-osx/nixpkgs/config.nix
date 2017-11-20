{
  allowUnfree = true;

  packageOverrides = pkgs: {
      vim = pkgs.vim_configurable.overrideDerivation (o: {
        aclSupport              = false;
        cscopeSupport           = true;
        darwinSupport           = false;
        fontsetSupport          = true;
        ftNixSupport            = true;
        gpmSupport              = true;
        hangulinputSupport      = false;
        luaSupport              = true;
        multibyteSupport        = true;
        mzschemeSupport         = true;
        netbeansSupport         = false;
        nlsSupport              = false;
        perlSupport             = false;
        pythonSupport           = true;
        rubySupport             = true;
        sniffSupport            = false;
        tclSupport              = false;
        ximSupport              = false;
        xsmpSupport             = false;
        xsmp_interactSupport    = false;
    });
  };
}
