print("Script Loader Started")
notify("Loading...","YCLoader",5)

local Scripts = {
    [847722000] = "https://raw.githubusercontent.com/SevereYC/Severe_git/refs/heads/main/The_Rake.lua",
    [2165551367] = "https://raw.githubusercontent.com/SevereYC/Severe_git/refs/heads/main/Granny.lua",
    [7008097940] = "https://raw.githubusercontent.com/SevereYC/Severe_git/refs/heads/main/InkGame.lua",
    [3047037061] = "https://raw.githubusercontent.com/SevereYC/Severe_git/refs/heads/main/Minesweeper.lua",
    [1116949753] = "https://raw.githubusercontent.com/SevereYC/Severe_git/refs/heads/main/IsleESP.lua",
    [3880544777] = "https://raw.githubusercontent.com/SevereYC/Severe_git/refs/heads/main/Instant%20Interact.lua",
    [9866118593] = "https://raw.githubusercontent.com/SevereYC/Severe_git/refs/heads/main/Instant%20Interact.lua",
    [6331902150] = "https://raw.githubusercontent.com/SevereYC/Severe_git/refs/heads/main/autoblock-rewrite.lua"
}

local GameId = game.GameId
print("Current GameId:", GameId)

local url = Scripts[GameId]

if url then
    print("found game")
    print("Loading script...")

    local success, err = pcall(function()
        loadstring(game:HttpGet(url))()
    end)

    if not success then
        warn("Script execution failed:", err)
    end
else
    warn("No script configured for this GameId.")
    notify("Unsupported games","YCLoader",5)
end
