open Stdune
open Dune_file_watcher_tests_lib

let%expect_test _ = init ()

let%expect_test _ =
  let mutex = Mutex.create () in
  let critical_section ~f =
    Mutex.lock mutex;
    Exn.protect ~f ~finally:(fun () -> Mutex.unlock mutex)
  in
  let events_buffer = ref [] in
  let watcher =
    Dune_file_watcher.create_default
      ~scheduler:
        { spawn_thread = (fun f -> ignore (Thread.create f () : Thread.t))
        ; thread_safe_send_emit_events_job =
            (fun job ->
              Mutex.lock mutex;
              let events = job () in
              events_buffer := !events_buffer @ events;
              Mutex.unlock mutex)
        }
  in
  let try_to_get_events () =
    critical_section ~f:(fun () ->
        match !events_buffer with
        | [] -> None
        | list ->
          events_buffer := [];
          Some
            (List.map list ~f:(function
              | Dune_file_watcher.Event.Sync -> assert false
              | Queue_overflow -> assert false
              | Fs_memo_event e -> e
              | Watcher_terminated -> assert false)))
  in
  let print_events n = print_events ~try_to_get_events ~expected:n in
  Dune_file_watcher.wait_for_initial_watches_established_blocking watcher;
  Stdio.Out_channel.write_all "x" ~data:"x";
  print_events 1;
  [%expect
    {|
    { path = In_source_tree "."; kind = "Created" }
    { path = In_source_tree "x"; kind = "Unknown" }
    Got more events than expected: expected 1, saw 2 |}];
  Unix.rename "x" "y";
  print_events 0;
  [%expect {|
|}];
  let (_ : _) = Fpath.mkdir_p "d/w" in
  Stdio.Out_channel.write_all "d/w/x" ~data:"x";
  print_events 0;
  [%expect {||}];
  Stdio.Out_channel.write_all "d/w/y" ~data:"y";
  print_events 1;
  [%expect
    {|
    { path = In_source_tree "x"; kind = "Unknown" }
    { path = In_source_tree "y"; kind = "Unknown" }
    { path = In_source_tree "d"; kind = "Created" }
    { path = In_source_tree "d/w"; kind = "Created" }
    { path = In_source_tree "d/w/x"; kind = "Unknown" }
    { path = In_source_tree "d/w/y"; kind = "Unknown" }
    Got more events than expected: expected 1, saw 6 |}]