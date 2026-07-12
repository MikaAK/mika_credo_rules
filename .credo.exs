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
        {MikaCredoRules.LoggerModulePrefixAndInspect, []},
        {MikaCredoRules.NoApplicationEnvOutsideConfig, []},
        {MikaCredoRules.NoBlanketRescue, []},
        {MikaCredoRules.NoMixEnvAtRuntime, []},
        {MikaCredoRules.NoMockingLibraries, []},
        {MikaCredoRules.NoNilComparison, []},
        {MikaCredoRules.NoProcessSleepInTests, []},
        {MikaCredoRules.NoReimplementedHelper, []},
        {MikaCredoRules.NoSingleLetterVariables, []},
        {MikaCredoRules.RefuteOverAssertNot, []},
        {MikaCredoRules.StrictEquality, []},
        {MikaCredoRules.TodosNeedTickets, []}
      ]
    }
  ]
}
