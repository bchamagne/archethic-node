defmodule Archethic.Contracts.ActionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.ActionInterpreter
  alias Archethic.Contracts.Interpreter

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GenesisAddress

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.TransactionFactory

  doctest ActionInterpreter

  import Mox

  test "should parse a contract with some standard functions" do
    assert {:ok, :transaction,
            {
              :__block__,
              [],
              [
                {
                  :=,
                  [line: 2],
                  [
                    {:scope, [line: 2], nil},
                    {
                      :update_in,
                      [line: 2],
                      [
                        {:scope, [line: 2], nil},
                        ["next_transaction"],
                        {:&, [line: 2],
                         [
                           {{:., [line: 2],
                             [
                               {:__aliases__,
                                [
                                  alias: Archethic.Contracts.Interpreter.TransactionStatements
                                ], [:TransactionStatements]},
                               :set_type
                             ]}, [line: 2], [{:&, [line: 2], [1]}, "transfer"]}
                         ]}
                      ]
                    }
                  ]
                },
                {
                  :=,
                  [line: 3],
                  [
                    {:scope, [line: 3], nil},
                    {
                      :update_in,
                      [line: 3],
                      [
                        {:scope, [line: 3], nil},
                        ["next_transaction"],
                        {
                          :&,
                          [line: 3],
                          [
                            {
                              {:., [line: 3],
                               [
                                 {:__aliases__,
                                  [
                                    alias: Archethic.Contracts.Interpreter.TransactionStatements
                                  ], [:TransactionStatements]},
                                 :add_uco_transfer
                               ]},
                              [line: 3],
                              [
                                {:&, [line: 3], [1]},
                                [
                                  {"to",
                                   "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3"},
                                  {"amount", 1_040_000_000}
                                ]
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                },
                {
                  :=,
                  [line: 4],
                  [
                    {:scope, [line: 4], nil},
                    {
                      :update_in,
                      [line: 4],
                      [
                        {:scope, [line: 4], nil},
                        ["next_transaction"],
                        {
                          :&,
                          [line: 4],
                          [
                            {
                              {:., [line: 4],
                               [
                                 {:__aliases__,
                                  [
                                    alias: Archethic.Contracts.Interpreter.TransactionStatements
                                  ], [:TransactionStatements]},
                                 :add_token_transfer
                               ]},
                              [line: 4],
                              [
                                {:&, [line: 4], [1]},
                                [
                                  {"to",
                                   "30670455713E2CBECF94591226A903651ED8625635181DDA236FECC221D1E7E4"},
                                  {"amount", 20_000_000_000},
                                  {"token_address",
                                   "AEB4A6F5AB6D82BE223C5867EBA5FE616F52F410DCF83B45AFF158DD40AE8AC3"},
                                  {"token_id", 0}
                                ]
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                },
                {
                  :=,
                  [line: 5],
                  [
                    {:scope, [line: 5], nil},
                    {
                      :update_in,
                      [line: 5],
                      [
                        {:scope, [line: 5], nil},
                        ["next_transaction"],
                        {
                          :&,
                          [line: 5],
                          [
                            {{:., [line: 5],
                              [
                                {:__aliases__,
                                 [
                                   alias: Archethic.Contracts.Interpreter.TransactionStatements
                                 ], [:TransactionStatements]},
                                :set_content
                              ]}, [line: 5], [{:&, [line: 5], [1]}, "Receipt"]}
                          ]
                        }
                      ]
                    }
                  ]
                },
                {
                  :=,
                  [line: 6],
                  [
                    {:scope, [line: 6], nil},
                    {
                      :update_in,
                      [line: 6],
                      [
                        {:scope, [line: 6], nil},
                        ["next_transaction"],
                        {
                          :&,
                          [line: 6],
                          [
                            {
                              {:., [line: 6],
                               [
                                 {:__aliases__,
                                  [
                                    alias: Archethic.Contracts.Interpreter.TransactionStatements
                                  ], [:TransactionStatements]},
                                 :add_ownership
                               ]},
                              [line: 6],
                              [
                                {:&, [line: 6], [1]},
                                [
                                  {"secret", "MyEncryptedSecret"},
                                  {"secret_key", "MySecretKey"},
                                  {"authorized_public_keys",
                                   [
                                     "70C245E5D970B59DF65638BDD5D963EE22E6D892EA224D8809D0FB75D0B1907A"
                                   ]}
                                ]
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                },
                {
                  :=,
                  [line: 7],
                  [
                    {:scope, [line: 7], nil},
                    {
                      :update_in,
                      [line: 7],
                      [
                        {:scope, [line: 7], nil},
                        ["next_transaction"],
                        {
                          :&,
                          [line: 7],
                          [
                            {
                              {:., [line: 7],
                               [
                                 {:__aliases__,
                                  [
                                    alias: Archethic.Contracts.Interpreter.TransactionStatements
                                  ], [:TransactionStatements]},
                                 :add_recipient
                               ]},
                              [line: 7],
                              [
                                {:&, [line: 7], [1]},
                                "78273C5CBCEB8617F54380CC2F173DF2404DB676C9F10D546B6F395E6F3BDDEE"
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }} =
             """
             actions triggered_by: transaction do
               set_type transfer
               add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 1040000000
               add_token_transfer to: \"30670455713E2CBECF94591226A903651ED8625635181DDA236FECC221D1E7E4\", amount: 20000000000, token_address: \"AEB4A6F5AB6D82BE223C5867EBA5FE616F52F410DCF83B45AFF158DD40AE8AC3\", token_id: 0
               set_content \"Receipt\"
               add_ownership secret: \"MyEncryptedSecret\", secret_key: \"MySecretKey\", authorized_public_keys: ["70C245E5D970B59DF65638BDD5D963EE22E6D892EA224D8809D0FB75D0B1907A"]
               add_recipient \"78273C5CBCEB8617F54380CC2F173DF2404DB676C9F10D546B6F395E6F3BDDEE\"
             end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
  end

  test "should evaluate actions based on if statement" do
    assert %Transaction{data: %TransactionData{content: "yes"}} =
             ~S"""
             actions triggered_by: transaction do
               if transaction.previous_public_key == "abc" do
                 set_content "yes"
               else
                 set_content "no"
               end
             end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute(%{"transaction" => %{"previous_public_key" => "abc"}})
  end

  test "should use a variable assignation" do
    assert %Transaction{data: %TransactionData{content: "hello"}} =
             """
               actions triggered_by: transaction do
                 new_content = \"hello\"
                 set_content new_content
               end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute()
  end

  test "should use a interpolation assignation" do
    assert %Transaction{data: %TransactionData{content: "hello 4"}} =
             ~S"""
               actions triggered_by: transaction do
                 new_content = "hello #{2+2}"
                 set_content new_content
               end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute()
  end

  test "get_calls() should be expanded to get_calls(contract.address)" do
    {:ok, :transaction, ast} =
      ~S"""
        actions triggered_by: transaction do
          get_calls()
        end
      """
      |> Interpreter.sanitize_code()
      |> elem(1)
      |> ActionInterpreter.parse()

    assert {{:., [line: 2],
             [
               {:__aliases__, [alias: Archethic.Contracts.Interpreter.Library], [:Library]},
               :get_calls
             ]}, [line: 2],
            [
              {:get_in, meta,
               [
                 {:scope, meta, nil},
                 ["contract", "address"]
               ]}
            ]} = ast
  end

  test "shall use get_genesis_address/1 in actions" do
    key = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: key,
      last_public_key: key,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    address = "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4"
    b_address = Base.decode16!(address)

    MockClient
    |> expect(:send_message, fn _, _, _ ->
      {:ok, %GenesisAddress{address: b_address}}
    end)

    assert %Transaction{data: %TransactionData{content: "yes"}} =
             ~s"""
             actions triggered_by: transaction do
               address = get_genesis_address("64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4")
               if address == "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4" do
                 set_content "yes"
               else
                 set_content "no"
               end
             end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute()
  end

  test "shall use get_calls/1 in actions" do
    key = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: key,
      last_public_key: key,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    address = Base.decode16!("64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4")

    MockDB
    |> stub(:get_inputs, fn _, ^address ->
      [
        %VersionedTransactionInput{
          protocol_version: ArchethicCase.current_protocol_version(),
          input: %TransactionInput{
            from: address,
            amount: nil,
            type: :call,
            timestamp: DateTime.utc_now(),
            spent?: false,
            reward?: false
          }
        }
      ]
    end)
    |> stub(:get_transaction, fn ^address, _, _ ->
      {:ok, TransactionFactory.create_valid_transaction()}
    end)

    # TODO: find a way to check the transactions returned by get_calls

    assert %Transaction{data: %TransactionData{content: "1"}} =
             ~s"""
             actions triggered_by: transaction do
               transactions = get_calls()
               set_content size(transactions)
             end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute(%{
               "contract" => %{
                 "address" => "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4"
               }
             })
  end

  describe "reduce/3" do
    test "should be able to create list of things" do
      ~S"""
      actions triggered_by: transaction do
        list = [1,2,3]
        list2 = ["foo", "bar"]
        list3 = [list, list2]
        set_content list3
      end
      """
      |> assert_content_after_execute("[[1,2,3],[\"foo\",\"bar\"]]")
    end

    test "should be able to reduce" do
      ~S"""
      actions triggered_by: transaction do
        list = [1337,2551,563]
        sum = reduce(list, 49, fn item, acc -> 0 + item + acc end)
        set_content sum
      end
      """
      |> assert_content_after_execute("4500")
    end

    test "should be able to filter" do
      ~S"""
      actions triggered_by: transaction do
        list = [1,2,3,4]
        even_numbers = reduce(list, [], fn number, acc ->
          if rem(number, 2) == 0 do
            append(acc, number)
          else
            acc
          end
        end)

        set_content even_numbers
      end
      """
      |> assert_content_after_execute("[2,4]")
    end

    test "should be able to map" do
      ~S"""
      actions triggered_by: transaction do
        list = [1,2,3]
        double = reduce(list, [], fn number, accu ->
            append(accu, number * 2)
        end)

        set_content double
      end
      """
      |> assert_content_after_execute("[2,4,6]")
    end

    test "should be able to use = in a reduce" do
      ~S"""
      actions triggered_by: transaction do
        list = [1,2,3]
        double = reduce(list, [], fn number, acc ->
            x = 2
            append(acc, number * x)
        end)

        set_content double
      end
      """
      |> assert_content_after_execute("[2,4,6]")
    end

    test "should be able to use . in a reduce" do
      ~S"""
      actions triggered_by: transaction do
        list = ["X", "Y"]
        content = reduce(list, [], fn unused, acc ->
          # unused assignment just to remove compilation warning
          x = unused

          append(acc, transaction.address)
        end)
        set_content content
      end
      """
      |> assert_content_after_execute("[\"@addr\",\"@addr\"]", %{
        "transaction" => %{
          "address" => "@addr"
        }
      })
    end

    test "should be able to use an object as 1st arg in a reduce" do
      ~S"""
      actions triggered_by: transaction do
        list = [transaction, transaction]
        content = reduce(list, [], fn tx, acc ->
            append(acc, tx.address)
        end)
        set_content content
      end
      """
      |> assert_content_after_execute("[\"@addr\",\"@addr\"]", %{
        "transaction" => %{
          "address" => "@addr"
        }
      })
    end

    test "should be able to use an object as 2nd arg in a reduce" do
      ~S"""
      actions triggered_by: transaction do
        list = ["X"]
        content = reduce(list, transaction, fn letter, acc ->
            # unused assignment just to remove compilation warning
            x = unused

            concat(acc.address, letter)
        end)
        set_content content
      end
      """
      |> assert_content_after_execute("@addrX", %{
        "transaction" => %{
          "address" => "@addr"
        }
      })
    end
  end

  defp assert_content_after_execute(code, content, constants \\ %{}) do
    assert %Transaction{data: %TransactionData{content: ^content}} =
             code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute(constants)
  end
end
