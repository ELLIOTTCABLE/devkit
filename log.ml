(** 
  Global ready-to-use logger 

  TODO interface to manage State
*)

(**
{2 Example usage}

Create logging facility (messages origin)
{[let http = Log.facility "http"]}

Log from http subsystem at debug level
{[Log.debug http "received %u bytes"]}

Create and use object for http logging
{[let log = Log.from "http" (* new Log.logger http *);;
log#info "sent %u bytes" 1024
log#warn ~exn "failed here"
]}

Output only messages of warning level or higher for the http facility
{[http#allow `Warn]}
or
{[Logger.set_filter http `Warn]}
or
{[Log.set_filter ~name:"http" `Warn]}

Output only messages of warning level or higher for all facilities
{[Log.set_filter `Warn]}

{2 API}
*)

open Printf
open ExtLib

(** Global logger state *)
module State = struct

  let all = Hashtbl.create 10
  let default_level = ref (`Info : Logger.level)

  let facility name =
    try
      Hashtbl.find all name
    with
      Not_found ->
        let x = { Logger.name = name; show = Logger.int_level !default_level } in
        Hashtbl.add all name x; 
        x

  let set_filter ?name level =
    match name with
    | None -> default_level := level; Hashtbl.iter (fun _ x -> Logger.set_filter x level) all
    | Some name -> Logger.set_filter (facility name) level

  let output_ch ch = 
    fun str -> output_string ch str; flush ch

  let format_simple level facil msg =
    sprintf "[%s] %06u:%04u %8s [%5s] %s\n" 
      (Time.gmt_string_ms (Unix.gettimeofday ())) 
      (Unix.getpid ()) 
      (Thread.id (Thread.self ()))
      facil.Logger.name
      (Logger.string_level level)
      msg

  let log_ch = ref stderr
  let output = ref (output_ch stderr)

  module Put = Logger.PutSimple(
  struct
    let format = format_simple
    let output = fun s -> !output s
  end)

  module M = Logger.Make(Put)

  let self = "lib"

  let reopen_log_ch file =
    try
      let ch = Files.open_out_append file in
      output := output_ch ch;
      if !log_ch <> stderr then close_out_noerr !log_ch;
      log_ch := ch
    with
      e -> M.warn (facility self) "reopen_log_ch(%s) failed : %s" file (Printexc.to_string e)

end

include State.M

let facility = State.facility
let set_filter = State.set_filter

type 'a pr = ?exn:exn -> ('a, unit, string, unit) format4 -> 'a

class logger facil =
let perform f =
  fun ?exn fmt -> match exn with
    | Some exn -> ksprintf (fun s -> f facil (s ^ " : exn " ^ Exn.str exn)) fmt
    | None -> ksprintf (f facil) fmt
in
object
method debug : 'a. 'a pr = perform debug_s
method warn : 'a. 'a pr = perform warn_s
method info : 'a. 'a pr = perform info_s
method error : 'a. 'a pr = perform error_s
method allow (level:Logger.level) = Logger.set_filter facil level
method level : Logger.level = Logger.get_level facil
method name = facil.Logger.name
end

let from name = new logger (facility name)

(** internal logging facility *)
let self = from State.self

(** general logging facility *)
let main = from "main"

