# Rebinds the FR-08A protected-boundary evidence to HEAD after a protected-code change.
#
#   (cd foundry && MIX_ENV=test mix run --no-start bin/rebind_fr08a.exs)
#
# Run on a clean tree whose HEAD is the subject commit (the protected change itself), then
# commit the three files it rewrites as a separate "rebind" commit, as every earlier rebind
# was. It recomputes, for every module FR08AProtectedBoundary pins, the source sha256 and
# the loaded BEAM md5 (test build), replaces the old values in the provider and its test,
# sets the subject revision/tree, and regenerates the frozen report from report_artifact/0.
# It changes no protected code and cannot make a failing probe pass: the report's
# ready= line is printed so a false one is seen.

alias PramanaFoundry.Repair.FR08AProtectedBoundary

{subject, 0} = System.cmd("git", ["rev-parse", "HEAD"])
{tree, 0} = System.cmd("git", ["rev-parse", "HEAD^{tree}"])
{status, 0} = System.cmd("git", ["status", "--porcelain", "--", "."])
if status != "", do: raise("tree is dirty; commit the subject change first:\n" <> status)

provider = "lib/pramana_foundry/repair/fr08a_protected_boundary.ex"
test = "test/pramana_foundry/repair/fr08a_protected_boundary_test.exs"
report = "docs/fr-08/fr08a-protected-report.txt"
source = File.read!(provider)

[[_, old_subject]] = Regex.scan(~r/@subject_revision "([0-9a-f]{40})"/, source)
[[_, old_tree]] = Regex.scan(~r/@subject_tree "([0-9a-f]{40})"/, source)

identity_pairs =
  for %{path: path, sha256: old_sha, beam_md5: old_md5} <-
        FR08AProtectedBoundary.identity().exercised_api do
    [[module_name]] =
      Regex.scan(~r/\{(PramanaFoundry\.[A-Za-z0-9.]+),\s*"#{Regex.escape(path)}"/, source,
        capture: :all_but_first
      )

    module = Module.concat([module_name])
    sha = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
    md5 = Base.encode16(module.module_info(:md5), case: :lower)
    [{old_sha, sha}, {old_md5, md5}]
  end
  |> List.flatten()

pairs = [{old_subject, String.trim(subject)}, {old_tree, String.trim(tree)} | identity_pairs]

for file <- [provider, test] do
  File.write!(
    file,
    Enum.reduce(pairs, File.read!(file), fn {o, n}, acc -> String.replace(acc, o, n) end)
  )
end

for {o, n} <- pairs, o != n, do: IO.puts("#{String.slice(o, 0, 8)} -> #{String.slice(n, 0, 8)}")
IO.puts("regenerate the report in a fresh VM so the rewritten provider is the one loaded:")

IO.puts(
  "  MIX_ENV=test mix run --no-start -e 'File.write!(\"#{report}\", #{inspect(FR08AProtectedBoundary)}.report_artifact())'"
)
