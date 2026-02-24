namespace Ralph.BacklogCli;

public static class FileLocking
{
    public static FileStream AcquireExclusiveLock(string lockFilePath)
    {
        var dir = Path.GetDirectoryName(lockFilePath);
        if (!string.IsNullOrWhiteSpace(dir))
        {
            Directory.CreateDirectory(dir);
        }

        return new FileStream(lockFilePath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
}
