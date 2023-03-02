defmodule Archethic.Contracts.Interpreter.Version1.CommonInterpreter do
  @moduledoc """
  The prewalk and postwalk functions receive an `acc` for convenience.
  They should see it as an opaque variable and just forward it.

  This way we can use this interpreter inside other interpreters, and each deal with the acc how they want to.
  """

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Version1.Library

  @modules_whitelisted Library.list_common_modules()

  # ----------------------------------------------------------------------
  #                                _ _
  #   _ __  _ __ _____      ____ _| | | __
  #  | '_ \| '__/ _ \ \ /\ / / _` | | |/ /
  #  | |_) | | |  __/\ V  V | (_| | |   <
  #  | .__/|_|  \___| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  # the atom marker (set by sanitize_code)
  def prewalk(:atom, acc), do: {:atom, acc}

  # expressions
  def prewalk(node = {:+, _, _}, acc), do: {node, acc}
  def prewalk(node = {:-, _, _}, acc), do: {node, acc}
  def prewalk(node = {:/, _, _}, acc), do: {node, acc}
  def prewalk(node = {:*, _, _}, acc), do: {node, acc}
  def prewalk(node = {:>, _, _}, acc), do: {node, acc}
  def prewalk(node = {:<, _, _}, acc), do: {node, acc}
  def prewalk(node = {:>=, _, _}, acc), do: {node, acc}
  def prewalk(node = {:<=, _, _}, acc), do: {node, acc}
  def prewalk(node = {:|>, _, _}, acc), do: {node, acc}
  def prewalk(node = {:==, _, _}, acc), do: {node, acc}
  def prewalk(node = {:!=, _, _}, acc), do: {node, acc}
  def prewalk(node = {:++, _, _}, acc), do: {node, acc}
  def prewalk(node = {:!, _, _}, acc), do: {node, acc}

  # ranges
  def prewalk(node = {:.., _, _}, acc), do: {node, acc}

  # blocks
  def prewalk(node = {:__block__, _, _}, acc), do: {node, acc}
  def prewalk(node = {:do, _}, acc), do: {node, acc}
  def prewalk(node = :do, acc), do: {node, acc}

  # literals
  # it is fine allowing atoms since the users can't create them (this avoid whitelisting functions/modules we use in the prewalk)
  def prewalk(node, acc) when is_atom(node), do: {node, acc}
  def prewalk(node, acc) when is_boolean(node), do: {node, acc}
  def prewalk(node, acc) when is_number(node), do: {node, acc}
  def prewalk(node, acc) when is_binary(node), do: {node, acc}

  # converts all keywords to maps
  def prewalk(node, acc) when is_list(node) do
    if AST.is_keyword_list?(node) do
      new_node = AST.keyword_to_map(node)
      {new_node, acc}
    else
      {node, acc}
    end
  end

  # pairs (used in maps)
  def prewalk(node = {key, _}, acc) when is_binary(key), do: {node, acc}

  # maps (required because we create maps for each scope in the ActionInterpreter's prewalk)
  def prewalk(node = {:%{}, _, _}, acc), do: {node, acc}

  # variables
  def prewalk(node = {{:atom, var_name}, _, nil}, acc) when is_binary(var_name), do: {node, acc}
  def prewalk(node = {:atom, var_name}, acc) when is_binary(var_name), do: {node, acc}

  # module call
  def prewalk(node = {{:., _, [{:__aliases__, _, _}, _]}, _, _}, acc), do: {node, acc}
  def prewalk(node = {:., _, [{:__aliases__, _, _}, _]}, acc), do: {node, acc}

  # whitelisted modules
  def prewalk(node = {:__aliases__, _, [atom: module_name]}, acc)
      when module_name in @modules_whitelisted,
      do: {node, acc}

  # internal modules (Process/Scope/Kernel)
  def prewalk(node = {:__aliases__, _, [atom]}, acc) when is_atom(atom), do: {node, acc}

  # internal functions
  def prewalk(node = {:put_in, _, _}, acc), do: {node, acc}
  def prewalk(node = {:get_in, _, _}, acc), do: {node, acc}
  def prewalk(node = {:update_in, _, _}, acc), do: {node, acc}

  # if
  def prewalk(_node = {:if, meta, [predicate, do_else_keyword]}, acc) do
    # wrap the do/else blocks
    do_else_keyword =
      Enum.map(do_else_keyword, fn {key, value} ->
        {key, AST.wrap_in_block(value)}
      end)

    new_node = {:if, meta, [predicate, do_else_keyword]}
    {new_node, acc}
  end

  # else (no wrap needed since it's done in the if)
  def prewalk(node = {:else, _}, acc), do: {node, acc}
  def prewalk(node = :else, acc), do: {node, acc}

  # string interpolation
  def prewalk(node = {{:., _, [Kernel, :to_string]}, _, _}, acc), do: {node, acc}
  def prewalk(node = {:., _, [Kernel, :to_string]}, acc), do: {node, acc}
  def prewalk(node = {:binary, _, nil}, acc), do: {node, acc}
  def prewalk(node = {:<<>>, _, _}, acc), do: {node, acc}
  def prewalk(node = {:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, _]}, acc), do: {node, acc}

  # blacklist rest
  def prewalk(node, _acc), do: throw({:error, node, "unexpected term"})

  # ----------------------------------------------------------------------
  #                   _                 _ _
  #   _ __   ___  ___| |___      ____ _| | | __
  #  | '_ \ / _ \/ __| __\ \ /\ / / _` | | |/ /
  #  | |_) | (_) \__ | |_ \ V  V | (_| | |   <
  #  | .__/ \___/|___/\__| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  def postwalk(
        node =
          {{:., meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _, args},
        acc
      )
      when module_name in @modules_whitelisted do
    absolute_module_atom =
      Code.ensure_loaded!(
        String.to_existing_atom(
          "Elixir.Archethic.Contracts.Interpreter.Version1.Library.Common.#{module_name}"
        )
      )

    # check function exists
    unless Library.function_exists?(absolute_module_atom, function_name) do
      throw({:error, node, "unknown function: #{module_name}.#{function_name}"})
    end

    # check function is available with given arity
    unless Library.function_exists?(absolute_module_atom, function_name, length(args)) do
      throw({:error, node, "invalid arity for function #{module_name}.#{function_name}"})
    end

    module_atom = String.to_existing_atom(module_name)
    function_atom = String.to_existing_atom(function_name)

    # check the type of the args
    unless absolute_module_atom.check_types(function_atom, args) do
      throw({:error, node, "invalid arguments for function #{module_name}.#{function_name}"})
    end

    meta_with_alias = Keyword.put(meta, :alias, absolute_module_atom)

    new_node =
      {{:., meta, [{:__aliases__, meta_with_alias, [module_atom]}, function_atom]}, meta, args}

    {new_node, acc}
  end

  # whitelist rest
  def postwalk(node, acc), do: {node, acc}

  # ----------------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ----------------------------------------------------------------------
end