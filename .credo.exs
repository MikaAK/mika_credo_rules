%{
  configs: [
    %{
      # NOTE: the name MUST be "default". Credo selects the config named "default"
      # unless --config-name is passed; a differently-named config is silently
      # IGNORED and Credo falls back to its own stock checks — reporting a green
      # run that never executed a single check below.
      name: "default",
      files: %{
        included: ["lib/", "test/", "mix.exs", ".credo.exs"],
        excluded: []
      },
      strict: true,
      checks: [
        {MikaCredoRules.EnsureLoadedBeforeExported, []},
        {MikaCredoRules.DistributionRequiresBuckets, []},
        {MikaCredoRules.EctoMetricsRequiresAppAtom, []},
        {MikaCredoRules.CredoConfigNamedDefault, []},
        {MikaCredoRules.AbsintheDataloaderPluginRequired, []},
        {MikaCredoRules.CacheOptsNoHardcodedUri, []},
        {MikaCredoRules.CacheRequiresSandboxOption, []},
        {MikaCredoRules.ErrorMessageRequired, []},
        {MikaCredoRules.ExceptionNamesEndInError, []},
        {MikaCredoRules.GenServerRequiresHandleContinue, []},
        {MikaCredoRules.InUmbrellaDepsNoVersion, []},
        {MikaCredoRules.LiveViewSubscribeRequiresConnected, []},
        {MikaCredoRules.LoggerModulePrefixAndInspect, []},
        {MikaCredoRules.NoAccessOnStructSubject, []},
        {MikaCredoRules.MigrationExecuteInChange, []},
        {MikaCredoRules.MigrationFlushBetweenExecuteAndQuery, []},
        {MikaCredoRules.MigrationForeignKeyNeedsIndex, []},
        {MikaCredoRules.MonolithicTemplateComponent, []},
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
        {MikaCredoRules.NoContinueFromLiveViewMount, []},
        {MikaCredoRules.NoEctoSchemaInWebApp, []},
        {MikaCredoRules.NoClickHandlerOnNonInteractiveElement, []},
        {MikaCredoRules.NoIdentityRewrap, []},
        {MikaCredoRules.NoInspectModuleInMigrationSql, []},
        {MikaCredoRules.NoJasonDeriveOnEctoSchema, []},
        {MikaCredoRules.NoKernelPrefix, []},
        {MikaCredoRules.NoMixEnvAtRuntime, []},
        {MikaCredoRules.NoMockingLibraries, []},
        {MikaCredoRules.NoNilComparison, []},
        {MikaCredoRules.NoObanInsertBang, []},
        {MikaCredoRules.NoProcessSleepInTests, []},
        {MikaCredoRules.NoRawEts, []},
        {MikaCredoRules.NoRawMarkupInTemplates, []},
        {MikaCredoRules.NoReimplementedHelper, []},
        {MikaCredoRules.NoRepoWritesInTests, []},
        {MikaCredoRules.NoSelfSendZeroDelay, []},
        {MikaCredoRules.NoSingleLetterVariables, []},
        {MikaCredoRules.NoVacuousAssert, []},
        {MikaCredoRules.NoWordSigilLists, []},
        {MikaCredoRules.NoTruthyAndOr, []},
        {MikaCredoRules.ObanWorkerRequiresMaxAttempts, []},
        {MikaCredoRules.NoStaticNotLoadedDropList, []},
        {MikaCredoRules.NoTaskAsyncInGenServer, []},
        {MikaCredoRules.NoUnsupervisedTaskStart, []},
        {MikaCredoRules.NoTelemetrySupervisorModule, []},
        {MikaCredoRules.PrometheusExporterMustBeGated, []},
        {MikaCredoRules.PhxValueNoDashes, []},
        {MikaCredoRules.RefuteOverAssertNot, []},
        {MikaCredoRules.SingleModulePerFile, []},
        {MikaCredoRules.SqlSandboxPlugMustBeCompileGated, []},
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
        {MikaCredoRules.TaskAsyncStreamRequiresTimeout, []},
        {MikaCredoRules.TodosNeedTickets, []}
      ]
    }
  ]
}
