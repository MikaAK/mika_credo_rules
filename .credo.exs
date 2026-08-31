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
        {MikaCredoRules.EnsureLoadedBeforeExported, []},
        {MikaCredoRules.DistributionRequiresBuckets, []},
        {MikaCredoRules.EctoMetricsRequiresAppAtom, []},
        {MikaCredoRules.ErrorMessageRequired, []},
        {MikaCredoRules.ExceptionNamesEndInError, []},
        {MikaCredoRules.GenServerRequiresHandleContinue, []},
        {MikaCredoRules.LoggerModulePrefixAndInspect, []},
        {MikaCredoRules.NoAccessOnStructSubject, []},
        {MikaCredoRules.NoApplicationEnvOutsideConfig, []},
        {MikaCredoRules.NoAtomStringKeyFallback, []},
        {MikaCredoRules.NoBarePatternMatchOnFallible, []},
        {MikaCredoRules.NoBinaryPatternForStringPrefix, []},
        {MikaCredoRules.NoBlanketRescue, []},
        {MikaCredoRules.NoBooleanLiteralComparison, []},
        {MikaCredoRules.NoCastAllKeys, []},
        {MikaCredoRules.NoCondElseAtom, []},
        {MikaCredoRules.NoForWithDiscardedResult, []},
        {MikaCredoRules.NoDirectErlangRpc, []},
        {MikaCredoRules.NoDirectHttpClient, []},
        {MikaCredoRules.NoIdentityRewrap, []},
        {MikaCredoRules.NoJasonDeriveOnEctoSchema, []},
        {MikaCredoRules.NoKernelPrefix, []},
        {MikaCredoRules.NoMixEnvAtRuntime, []},
        {MikaCredoRules.NoMockingLibraries, []},
        {MikaCredoRules.NoNilComparison, []},
        {MikaCredoRules.NoObanInsertBang, []},
        {MikaCredoRules.NoProcessSleepInTests, []},
        {MikaCredoRules.NoRawEts, []},
        {MikaCredoRules.NoReimplementedHelper, []},
        {MikaCredoRules.NoRepoWritesInTests, []},
        {MikaCredoRules.NoSingleLetterVariables, []},
        {MikaCredoRules.NoVacuousAssert, []},
        {MikaCredoRules.NoWordSigilLists, []},
        {MikaCredoRules.NoTruthyAndOr, []},
        {MikaCredoRules.ObanWorkerRequiresMaxAttempts, []},
        {MikaCredoRules.RefuteOverAssertNot, []},
        {MikaCredoRules.SingleModulePerFile, []},
        {MikaCredoRules.StrictEquality, []},
        {MikaCredoRules.TodosNeedTickets, []}
      ]
    }
  ]
}
