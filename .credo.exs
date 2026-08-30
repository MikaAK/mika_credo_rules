%{
  configs: [
    %{
      # NOTE: the name MUST be "default". Credo selects the config named "default"
      # unless --config-name is passed; a differently-named config is silently
      # IGNORED and Credo falls back to its own stock checks — reporting a green
      # run that never executed a single check below.
      name: "default",
      files: %{
        included: ["lib/", "test/", "mix.exs"],
        excluded: []
      },
      strict: true,
      checks: [
        {MikaCredoRules.ErrorMessageRequired, []},
        {MikaCredoRules.GenServerRequiresHandleContinue, []},
        {MikaCredoRules.InUmbrellaDepsNoVersion, []},
        {MikaCredoRules.LoggerModulePrefixAndInspect, []},
        {MikaCredoRules.NoApplicationEnvOutsideConfig, []},
        {MikaCredoRules.NoAtomStringKeyFallback, []},
        {MikaCredoRules.NoBlanketRescue, []},
        {MikaCredoRules.NoCastAllKeys, []},
        {MikaCredoRules.NoIdentityRewrap, []},
        {MikaCredoRules.NoJasonDeriveOnEctoSchema, []},
        {MikaCredoRules.NoMixEnvAtRuntime, []},
        {MikaCredoRules.NoMockingLibraries, []},
        {MikaCredoRules.NoNilComparison, []},
        {MikaCredoRules.NoProcessSleepInTests, []},
        {MikaCredoRules.NoReimplementedHelper, []},
        {MikaCredoRules.NoSingleLetterVariables, []},
        {MikaCredoRules.RefuteOverAssertNot, []},
        {MikaCredoRules.SingleModulePerFile, []},
        {MikaCredoRules.StrictEquality, []},
        # :credo is dropped from :test_only_packages for this repo only: this
        # package's own modules `use Credo.Check`, so :credo must compile in
        # every env this package itself is compiled in (not test-only like a
        # normal consumer's dependency) — `runtime: false` alone is correct.
        {MikaCredoRules.TestOnlyDepsScoped,
         [
           test_only_packages: [
             :wallaby,
             :dialyxir,
             :mix_test_watch,
             :excoveralls,
             :ex_doc,
             :mika_credo_rules
           ]
         ]},
        {MikaCredoRules.TodosNeedTickets, []}
      ]
    }
  ]
}
