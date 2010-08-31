AC_INIT(testmake, v0.0.1, fil@fiji-systems.com)

AC_PREREQ(2.52)
AC_CONFIG_SRCDIR([./README])

AC_PROG_INSTALL

if test -z "$RUBY"
then
  AC_MSG_CHECKING(for ruby)
  AC_TRY_COMMAND(ruby --version > /dev/null)
  if test $? == 0
  then
    AC_MSG_RESULT(ruby)
    RUBY=ruby
  else
    AC_TRY_COMMAND(ruby1.8 --version > /dev/null)
    if test $? == 0
    then
      AC_MSG_RESULT(ruby1.8)
      RUBY=ruby1.8
    else
      AC_MSG_ERROR([Could not find ruby; try setting the RUBY environment variable])
    fi
  fi
fi

AC_SUBST(RUBY)

AC_CONFIG_FILES([Makefile lib/config.rb bin/recall bin/testmake bin/tester bin/summarize])

AC_OUTPUT

