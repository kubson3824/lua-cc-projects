function downloadFile(url, destination)
    local response = http.get(url)
    if response then
        local file = fs.open(destination, "w")
        file.write(response.readAll())
        file.close()
        response.close()
        print("Downloaded file to " .. destination)
    else
        print("Failed to download file from " .. url)
    end
end

-- Main script
local args = {...}

if #args < 2 then
    print("Usage: download <GitHub URL> <destination>")
    return
end

local url = args[1]
local destination = args[2]

-- Download the file
downloadFile(url, destination)
