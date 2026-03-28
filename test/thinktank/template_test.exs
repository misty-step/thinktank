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

    for expected <- [
          "text=hello",
          "int=7",
          "float=1.5",
          "bool=true",
          "list=a\n2",
          ~s("ok": true),
          "nil="
        ] do
      assert rendered =~ expected
    end
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

  test "falls back to inspect when map values are not JSON encodable" do
    rendered = Template.render("map={{map}}", %{"map" => %{pid: self()}})
    assert rendered =~ "map=%{pid:"
  end
end
