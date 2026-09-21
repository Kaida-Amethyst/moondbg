///|
async test "project source ownership excludes dependencies tests and inactive sources" {
  let directory = @fs.tmpdir(prefix="moondbg sources ")
  defer @fs.rmdir(directory, recursive=true)
  for name in ["local.mbt", "core.mbt", "test.mbt", "js.mbt", "release.mbt"] {
    @fs.write_file("\{directory}/\{name}", "")
  }
  @fs.symlink(target="\{directory}/local.mbt", "\{directory}/link.mbt")
  let native : Json = { "backend": ["Native"], "optlevel": ["Debug"] }
  let files : Map[String, Json] = Map([])
  files.set("\{directory}/local.mbt", native)
  files.set("\{directory}/link.mbt", native)
  files.set("\{directory}/js.mbt", { "backend": ["Js"], "optlevel": ["Debug"] })
  files.set("\{directory}/release.mbt", {
    "backend": ["Native"],
    "optlevel": ["Release"],
  })
  let metadata : Json = {
    "packages": [
      {
        "is-third-party": false,
        "files": Json(files),
        "wbtest-files": Json(Map([("\{directory}/test.mbt", native)])),
      },
      {
        "is-third-party": true,
        "files": Json(Map([("\{directory}/core.mbt", native)])),
      },
    ],
  }
  let sources = local_debug_sources(metadata.stringify())
  assert_true(sources.contains("\{directory}/local.mbt"))
  assert_true(sources.contains("\{directory}/link.mbt"))
  assert_true(sources.contains(@fs.realpath("\{directory}/local.mbt")))
  for name in ["core.mbt", "test.mbt", "js.mbt", "release.mbt"] {
    assert_false(sources.contains("\{directory}/\{name}"))
  }
}
