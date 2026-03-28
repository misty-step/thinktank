defmodule Thinktank.TemplateTest do
  use ExUnit.Case, async: true

  alias Thinktank.Template

  test "renders supported value types into placeholders" do
    rendered =
      Template.render(
        """
        text={{text}}
        int={{int}}
        float={{float}}
        bool={{bool}}
        list={{list}}
        map={{map}}
        nil={{nil}}
        """,
        %{
          "text" => "hello",
          "int" => 7,
          "float" => 1.5,
          "bool" => true,
          "list" => ["a", 2],
          "map" => %{"ok" => true},
          "nil" => nil
        }
      )

    assert rendered =~ "text=hello"
    assert rendered =~ "int=7"
    assert rendered =~ "float=1.5"
    assert rendered =~ "bool=true"
    assert rendered =~ "list=a\n2"
    assert rendered =~ ~s("ok": true)
    assert rendered =~ "nil="
  end

  test "replaces missing placeholders with empty strings without touching values" do
    rendered =
      Template.render(
        """
        repo={{repo}}
        text={{text}}
        head={{head}}
        """,
        %{"text" => "literal {{repo}}"}
      )

    [repo_line, text_line, head_line] = String.split(rendered, "\n", trim: true)
    assert repo_line == "repo="
    assert text_line == "text=literal {{repo}}"
    assert head_line == "head="
  end
end
