# build-ruby.rb

Build Ruby from source code.

# Usage

```
ruby build-ruby.rb [options...] [REPOSITORY] [TARGET_NAME]
```

* REPOSITORY is svn or git repository. Default is `https://svn.ruby-lang.org/repos/ruby/trunk`.
* TARGET_NAME is a directory name for src/build/install. Default is basename of repository (trunk).
* Make the following directories:
  * ~/ruby/src/trunk
  * ~/ruby/build/trunk
  * ~/ruby/install/trunk
  * `~/ruby` can be specified by --root_directory option.
