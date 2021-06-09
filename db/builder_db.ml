module Rep = Representation
open Rep

let application_id = 1234839235l

(* Please update this when making changes! *)
let current_version = 6L

type id = Rep.id

type file = Rep.file = {
  filepath : Fpath.t;
  localpath : Fpath.t;
  sha256 : Cstruct.t;
  size : int;
}

let last_insert_rowid =
  Caqti_request.find
    Caqti_type.unit
    id
    "SELECT last_insert_rowid()"


let get_application_id =
  Caqti_request.find
    Caqti_type.unit
    Caqti_type.int32
    "PRAGMA application_id"

let get_version =
  Caqti_request.find
    Caqti_type.unit
    Caqti_type.int64
    "PRAGMA user_version"

let set_application_id =
  Caqti_request.exec
    Caqti_type.unit
    (Printf.sprintf "PRAGMA application_id = %ld" application_id)

let set_current_version =
  Caqti_request.exec
    Caqti_type.unit
    (Printf.sprintf "PRAGMA user_version = %Ld" current_version)

module Job = struct
  let migrate =
    Caqti_request.exec
      Caqti_type.unit
      {| CREATE TABLE job (
           id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
           name VARCHAR(255) NOT NULL UNIQUE
         )
      |}

  let rollback =
    Caqti_request.exec
      Caqti_type.unit
      {| DROP TABLE IF EXISTS job |}

  let get =
    Caqti_request.find
      id
      Caqti_type.string
      "SELECT name FROM job WHERE id = ?"

  let get_id_by_name =
    Caqti_request.find_opt
      Caqti_type.string
      id
      "SELECT id FROM job WHERE name = ?"

  let get_all =
    Caqti_request.collect
      Caqti_type.unit
      Caqti_type.(tup2 id string)
      "SELECT id, name FROM job ORDER BY name ASC"

  let try_add =
    Caqti_request.exec
      Caqti_type.string
      "INSERT OR IGNORE INTO job (name) VALUES (?)"

  let remove =
    Caqti_request.exec
      id
      "DELETE FROM job WHERE id = ?"
end

module Build_artifact = struct
  let migrate =
    Caqti_request.exec
      Caqti_type.unit
      {| CREATE TABLE build_artifact (
             id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
             filepath TEXT NOT NULL, -- the path as in the build
             localpath TEXT NOT NULL, -- local path to the file on disk
             sha256 BLOB NOT NULL,
             size INTEGER NOT NULL,
             build INTEGER NOT NULL,

             FOREIGN KEY(build) REFERENCES build(id),
             UNIQUE(build, filepath)
           )
        |}

  let rollback =
    Caqti_request.exec
      Caqti_type.unit
      "DROP TABLE IF EXISTS build_artifact"

  let get_by_build =
    Caqti_request.find
      (Caqti_type.tup2 id fpath)
      (Caqti_type.tup2 id file)
      {| SELECT id, filepath, localpath, sha256, size
         FROM build_artifact
         WHERE build = ? AND filepath = ?
      |}

  let get_by_build_uuid =
    Caqti_request.find_opt
      (Caqti_type.tup2 uuid fpath)
      (Caqti_type.tup2 id file)
      {| SELECT build_artifact.id, build_artifact.filepath,
           build_artifact.localpath, build_artifact.sha256, build_artifact.size
         FROM build_artifact
         INNER JOIN build ON build.id = build_artifact.build
         WHERE build.uuid = ? AND build_artifact.filepath = ?
      |}

  let get_all_by_build =
    Caqti_request.collect
      id
      Caqti_type.(tup2
                    id
                    file)
      "SELECT id, filepath, localpath, sha256, size FROM build_artifact WHERE build = ?"

  let add =
    Caqti_request.exec
      Caqti_type.(tup2 file id)
      "INSERT INTO build_artifact (filepath, localpath, sha256, size, build)
        VALUES (?, ?, ?, ?, ?)"

  let remove_by_build =
    Caqti_request.exec
      id
      "DELETE FROM build_artifact WHERE build = ?"
end

module Build_file = struct
  let migrate =
    Caqti_request.exec
      Caqti_type.unit
      {| CREATE TABLE build_file (
             id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
             filepath TEXT NOT NULL, -- the path as in the build
             localpath TEXT NOT NULL, -- local path to the file on disk
             sha256 BLOB NOT NULL,
             size INTEGER NOT NULL,
             build INTEGER NOT NULL,

             FOREIGN KEY(build) REFERENCES build(id),
             UNIQUE(build, filepath)
           )
        |}

  let rollback =
    Caqti_request.exec
      Caqti_type.unit
      "DROP TABLE IF EXISTS build_file"

  let get_by_build_uuid =
    Caqti_request.find_opt
      (Caqti_type.tup2 uuid fpath)
      (Caqti_type.tup2 id file)
      {| SELECT build_file.id, build_file.localpath,
           build_file.localpath, build_file.sha256, build_file.size
         FROM build_file
         INNER JOIN build ON build.id = build_file.build
         WHERE build.uuid = ? AND build_file.filepath = ?
      |}

  let get_all_by_build =
    Caqti_request.collect
      id
      Caqti_type.(tup2
                    id
                    file)
      "SELECT id, filepath, localpath, sha256, size FROM build_file WHERE build = ?"

  let add =
    Caqti_request.exec
      Caqti_type.(tup2 file id)
      "INSERT INTO build_file (filepath, localpath, sha256, size, build)
        VALUES (?, ?, ?, ?, ?)"

  let remove_by_build =
    Caqti_request.exec
      id
      "DELETE FROM build_file WHERE build = ?"
end

module Build = struct
  type t = {
    uuid : Uuidm.t;
    start : Ptime.t;
    finish : Ptime.t;
    result : Builder.execution_result;
    console : (int * string) list;
    script : string;
    main_binary : id option;
    job_id : id;
  }

  let t =
    let rep =
      Caqti_type.(tup2
                    (tup4
                       uuid
                       (tup2
                          Rep.ptime
                          Rep.ptime)
                       (tup2
                          execution_result
                          console)
                       (tup2
                          string
                          (option Rep.id)))
                    id)
    in
    let encode { uuid; start; finish; result; console; script; main_binary; job_id } =
      Ok ((uuid, (start, finish), (result, console), (script, main_binary)), job_id)
    in
    let decode ((uuid, (start, finish), (result, console), (script, main_binary)), job_id) =
      Ok { uuid; start; finish; result; console; script; main_binary; job_id }
    in
    Caqti_type.custom ~encode ~decode rep

  module Meta = struct
    type t = {
      uuid : Uuidm.t;
      start : Ptime.t;
      finish : Ptime.t;
      result : Builder.execution_result;
      main_binary : id option;
      job_id : id;
    }

    let t =
      let rep =
        Caqti_type.(tup2
                     (tup4
                       uuid
                       (tup2
                          Rep.ptime
                          Rep.ptime)
                       execution_result
                       (option Rep.id))
                     id)
      in
      let encode { uuid; start; finish; result; main_binary; job_id } =
        Ok ((uuid, (start, finish), result, main_binary), job_id)
      in
      let decode ((uuid, (start, finish), result, main_binary), job_id) =
        Ok { uuid; start; finish; result; main_binary; job_id }
      in
      Caqti_type.custom ~encode ~decode rep
  end

  let migrate =
    Caqti_request.exec
      Caqti_type.unit
      {| CREATE TABLE build (
           id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
           uuid VARCHAR(36) NOT NULL UNIQUE,
           start_d INTEGER NOT NULL,
           start_ps INTEGER NOT NULL,
           finish_d INTEGER NOT NULL,
           finish_ps INTEGER NOT NULL,
           result_kind TINYINT NOT NULL,
           result_code INTEGER,
           result_msg TEXT,
           console BLOB NOT NULL,
           script TEXT NOT NULL,
           main_binary INTEGER,
           job INTEGER NOT NULL,

           FOREIGN KEY(main_binary) REFERENCES build_artifact(id),
           FOREIGN KEY(job) REFERENCES job(id)
         )
      |}

  let rollback =
    Caqti_request.exec
      Caqti_type.unit
      {| DROP TABLE IF EXISTS build |}

  let get_opt =
    Caqti_request.find_opt
      Caqti_type.int64
      t
      {| SELECT uuid, start_d, start_ps, finish_d, finish_ps,
                result_kind, result_code, result_msg,
                console, script, main_binary, job
           FROM build
           WHERE id = ?
        |}

  let get_by_uuid =
    Caqti_request.find_opt
      Rep.uuid
      (Caqti_type.tup2 id t)
      {| SELECT id, uuid, start_d, start_ps, finish_d, finish_ps,
                  result_kind, result_code, result_msg,
                  console, script, main_binary, job
           FROM build
           WHERE uuid = ?
        |}

  let get_all =
    Caqti_request.collect
      Caqti_type.int64
      (Caqti_type.tup2 id t)
      {| SELECT id, uuid, start_d, start_ps, finish_d, finish_ps,
                  result_kind, result_code, result_msg, console,
                  script, main_binary, job
           FROM build
           WHERE job = ?
           ORDER BY start_d DESC, start_ps DESC
        |}

  let get_all_meta =
    Caqti_request.collect
      Caqti_type.int64
      (Caqti_type.tup3
         id Meta.t file_opt)
      {| SELECT build.id, build.uuid,
                build.start_d, build.start_ps, build.finish_d, build.finish_ps,
                build.result_kind, build.result_code, build.result_msg,
                build.main_binary, build.job,
                build_artifact.filepath, build_artifact.localpath, build_artifact.sha256, build_artifact.size
           FROM build, job
           LEFT JOIN build_artifact ON
             build.main_binary = build_artifact.id
           WHERE job.id = ? AND build.job = job.id
           ORDER BY start_d DESC, start_ps DESC
        |}

  let get_latest =
    Caqti_request.find_opt
      id
      Caqti_type.(tup3
                   id
                   Meta.t
                   file_opt)
      {| SELECT b.id,
           b.uuid, b.start_d, b.start_ps, b.finish_d, b.finish_ps,
           b.result_kind, b.result_code, b.result_msg,
           b.main_binary, b.job,
           a.filepath, a.localpath, a.sha256, a.size
         FROM build b
         LEFT JOIN build_artifact a ON
           b.main_binary = a.id
         WHERE b.job = ?
         ORDER BY start_d DESC, start_ps DESC
         LIMIT 1
      |}

  let get_latest_uuid =
    Caqti_request.find_opt
      id
      Caqti_type.(tup2 id Rep.uuid)
      {| SELECT b.id, b.uuid
         FROM build b
         WHERE b.job = ?
         ORDER BY start_d DESC, start_ps DESC
         LIMIT 1
      |}

  let get_latest_successful_uuid =
    Caqti_request.find_opt
      id
      Rep.uuid
      {| SELECT b.uuid
         FROM build b
         WHERE b.job = ? AND b.result_kind = 0 AND b.result_code = 0
         ORDER BY start_d DESC, start_ps DESC
         LIMIT 1
      |}

  let get_previous_successful =
    Caqti_request.find_opt
      id
      Caqti_type.(tup2 id Meta.t)
      {| SELECT b.id,
           b.uuid, b.start_d, b.start_ps, b.finish_d, b.finish_ps,
           b.result_kind, b.result_code, b.result_msg,
           b.main_binary, b.job
         FROM build b, build b0
         WHERE b0.id = ? AND b0.job = b.job AND
           b.result_kind = 0 AND b.result_code = 0 AND
           (b0.start_d > b.start_d OR b0.start_d = b.start_d AND b0.start_ps > b.start_ps)
         ORDER BY b.start_d DESC, b.start_ps DESC
         LIMIT 1
      |}

  let add =
    Caqti_request.exec
      t
      {| INSERT INTO build
           (uuid, start_d, start_ps, finish_d, finish_ps,
           result_kind, result_code, result_msg, console, script, main_binary, job)
           VALUES
           (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        |}

  let get_by_hash =
    Caqti_request.find_opt
      Rep.cstruct
      (Caqti_type.tup2
         Caqti_type.string
         t)
      {| SELECT job.name,
           b.uuid, b.start_d, b.start_ps, b.finish_d, b.finish_ps,
           b.result_kind, b.result_code, b.result_msg,
           b.console, b.script, b.main_binary, b.job
         FROM build_artifact a
         INNER JOIN build b ON b.id = a.build
         INNER JOIN job ON job.id = b.job
         WHERE a.sha256 = ?
         ORDER BY b.start_d DESC, b.start_ps DESC
         LIMIT 1
      |}

  let set_main_binary =
    Caqti_request.exec
      (Caqti_type.tup2 id id)
      "UPDATE build SET main_binary = ?2 WHERE id = ?1"

  let remove =
    Caqti_request.exec
      id
      "DELETE FROM build WHERE id = ?"
end

module User = struct
  let migrate =
    Caqti_request.exec
      Caqti_type.unit
      {| CREATE TABLE user (
           id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
           username VARCHAR(255) NOT NULL UNIQUE,
           password_hash BLOB NOT NULL,
           password_salt BLOB NOT NULL,
           scrypt_n INTEGER NOT NULL,
           scrypt_r INTEGER NOT NULL,
           scrypt_p INTEGER NOT NULL,
           restricted BOOLEAN NOT NULL
         )
      |}

  let rollback =
    Caqti_request.exec
      Caqti_type.unit
      "DROP TABLE IF EXISTS user"

  let get_user =
    Caqti_request.find_opt
      Caqti_type.string
      (Caqti_type.tup2 id user_info)
      {| SELECT id, username, password_hash, password_salt,
           scrypt_n, scrypt_r, scrypt_p, restricted
         FROM user
         WHERE username = ?
      |}

  let get_all =
    Caqti_request.collect
      Caqti_type.unit
      Caqti_type.string
      "SELECT username FROM user"

  let add =
    Caqti_request.exec
      user_info
      {| INSERT INTO user (username, password_hash, password_salt,
           scrypt_n, scrypt_r, scrypt_p, restricted)
         VALUES (?, ?, ?, ?, ?, ?, ?)
      |}

  let remove =
    Caqti_request.exec
      id
      "DELETE FROM user WHERE id = ?"

  let remove_user =
    Caqti_request.exec
      Caqti_type.string
      "DELETE FROM user WHERE username = ?"

  let update_user =
    Caqti_request.exec
      user_info
      {| UPDATE user
         SET password_hash = ?2,
             password_salt = ?3,
             scrypt_n = ?4,
             scrypt_r = ?5,
             scrypt_p = ?6,
             restricted = ?7
         WHERE username = ?1
      |}
end

module Access_list = struct
  let migrate =
    Caqti_request.exec
      Caqti_type.unit
      {| CREATE TABLE access_list (
             id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
             user INTEGER NOT NULL,
             job INTEGER NOT NULL,

             FOREIGN KEY(user) REFERENCES user(id),
             FOREIGN KEY(job) REFERENCES job(id),
             UNIQUE(user, job)
           )
      |}

  let rollback =
    Caqti_request.exec
      Caqti_type.unit
      "DROP TABLE IF EXISTS access_list"

  let get =
    Caqti_request.find
      Caqti_type.(tup2 Rep.id Rep.id)
      Rep.id
      "SELECT id FROM access_list WHERE user = ? AND job = ?"

  let add =
    Caqti_request.exec
      Caqti_type.(tup2 Rep.id Rep.id)
      "INSERT INTO access_list (user, job) VALUES (?, ?)"

  let remove =
    Caqti_request.exec
      Caqti_type.(tup2 Rep.id Rep.id)
      "DELETE FROM access_list WHERE user = ? AND job = ?"

  let remove_all_by_username =
    Caqti_request.exec
      Caqti_type.string
      "DELETE FROM access_list, user WHERE access_list.user = user.id AND user.username = ?"

end

let migrate = [
  Job.migrate;
  Build.migrate;
  Build_artifact.migrate;
  Build_file.migrate;
  User.migrate;
  Access_list.migrate;
  Caqti_request.exec Caqti_type.unit
    "CREATE INDEX idx_build_job_start ON build(job, start_d DESC, start_ps DESC)";
  set_current_version;
  set_application_id;
]

let rollback = [
  Access_list.rollback;
  User.rollback;
  Build_file.migrate;
  Build_artifact.rollback;
  Build.rollback;
  Job.rollback;
  Caqti_request.exec Caqti_type.unit
    "DROP INDEX IF EXISTS idx_build_job_start";
  Caqti_request.exec Caqti_type.unit
    "PRAGMA user_version = 0";
  Caqti_request.exec Caqti_type.unit
    "PRAGMA application_id = 0";
]
