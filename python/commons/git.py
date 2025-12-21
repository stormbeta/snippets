import logging
import tarfile
from subprocess import Popen, PIPE
from typing import Optional

log = logging.getLogger()

def git_pluck(repo: str, path: str, revision: str = "master") -> Optional[bytes]:
    """
    Reads a single file from a remote git repo directly into a byte-string
    :param repo:     full git url, same as you'd use to clone from
    :param path:     path to file within git repo
    :param revision: ref/branch name, defaults to 'master'
    :return:         byte-string contents of file, or None if not found / not a file
    """
    git_archive = Popen(['git', 'archive', f"--remote={repo}", revision, path], stdout=PIPE, stderr=PIPE)
    return_code = git_archive.wait()
    if return_code != 0:
        log.error(bytes.decode(git_archive.stderr.read()))
        exit(return_code)
    with tarfile.open(mode='r|', fileobj=git_archive.stdout) as tar:
        metadata: tarfile.TarInfo = tar.next()
        # NOTE: This loop=>next construct is required as stream is one-directional
        #       If you try to use TarFile.extractmember(...), it will raise an exception
        while metadata is not None:
            if metadata.name == path:
                file = tar.extractfile(metadata)
                if file is not None:
                    return file.read()
                else:
                    log.error("Remote path exists but is empty - you probably specified a directory by mistake")
            metadata = tar.next()
        return None
