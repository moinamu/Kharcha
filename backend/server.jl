using HTTP, JSON3, Base64, Dates, UUIDs, SHA

# Single owner app. Never put these credentials in docs/ or commit .env.
const TOKEN = ENV["GITHUB_TOKEN"]
const REPO = ENV["GITHUB_REPO"]
const KEY = ENV["APP_PASSWORD"]
const ORIGIN = ENV["ALLOWED_ORIGIN"]
const BRANCH = get(ENV,"GITHUB_BRANCH","main")
length(KEY) >= 24 || error("APP_PASSWORD must contain at least 24 characters")
occursin(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", REPO) || error("Invalid GITHUB_REPO")
const API = "https://api.github.com/repos/$(REPO)/contents/expenses.json"
const MUTEX = ReentrantLock()
const attempts = Dict{String,Vector{Float64}}()
const gate = ReentrantLock()
headers() = ["Authorization"=>"Bearer $TOKEN", "Accept"=>"application/vnd.github+json", "X-GitHub-Api-Version"=>"2022-11-28", "User-Agent"=>"Roz-Kharcha", "Content-Type"=>"application/json"]
function gh(method, url, body="")
    HTTP.request(method,url,headers(),body; status_exception=false,readtimeout=25,retry=false)
end
function readledger()
    r = gh("GET", API * "?ref=" * HTTP.escapeuri(BRANCH))
    r.status == 404 && return (Dict{String,Any}("entries"=>Any[]),nothing)
    r.status == 200 || error("GitHub read failed")
    obj = JSON3.read(String(r.body),Dict{String,Any})
    data = JSON3.read(String(base64decode(replace(obj["content"],"\n"=>""))),Dict{String,Any})
    (data,obj["sha"])
end
function valid(b)
    Date(b["date"],dateformat"yyyy-mm-dd")
    p=b["paise"]
    p isa Integer && !(p isa Bool) && 0 < p <= 100_000_000 || error("Invalid amount")
    b["category"] in ["Grocery","Food","Household","Other"] || error("Invalid category")
    0 < length(strip(b["store"])) <= 80 || error("Invalid store")
    length(b["note"]) <= 500 || error("Note too long")
end
function change!(data,b)
    rows=data["entries"]; action=get(b,"action","save"); id=get(b,"id","")
    idx=findfirst(e->e["id"]==id,rows)
    if action=="delete"
        isnothing(idx) && throw(ArgumentError("Entry not found")); deleteat!(rows,idx)
    elseif action=="check"
        isnothing(idx) && throw(ArgumentError("Entry not found")); b["checked"] isa Bool || error("Invalid checked value")
        rows[idx]["checked"]=b["checked"]
    elseif action=="save"
        valid(b)
        isempty(id) || !isnothing(idx) || throw(ArgumentError("Entry not found"))
        row=Dict{String,Any}("id"=>isempty(id) ? string(uuid4()) : id,"date"=>b["date"],"store"=>strip(b["store"]),"category"=>b["category"],"note"=>b["note"],"paise"=>b["paise"],"checked"=>false)
        isnothing(idx) ? push!(rows,row) : (rows[idx]=row)
    else
        error("Unknown action")
    end
    data
end
function writeledger(b)
    lock(MUTEX) do
        for n in 1:3
            data,sha=readledger()
            change!(data,b)
            payload=Dict{String,Any}("message"=>"Update expense ledger","content"=>base64encode(JSON3.write(data)),"branch"=>BRANCH)
            isnothing(sha) || (payload["sha"]=sha)
            r=gh("PUT",API,JSON3.write(payload))
            r.status in (200,201) && return data
            r.status==409 || error("GitHub save failed")
        end
        error("Ledger changed concurrently; retry")
    end
end
function equalkey(a,b)
    aa=sha256(a); bb=sha256(b); acc=UInt8(0)
    for i in eachindex(aa); acc |= aa[i] ⊻ bb[i]; end
    acc==0
end
function handler(req)
    origin=HTTP.header(req,"Origin","")
    hs=["Content-Type"=>"application/json", "Cache-Control"=>"no-store", "Vary"=>"Origin", "X-Content-Type-Options"=>"nosniff"]
    if origin==ORIGIN
        append!(hs,["Access-Control-Allow-Origin"=>ORIGIN,"Access-Control-Allow-Methods"=>"GET, POST, OPTIONS","Access-Control-Allow-Headers"=>"Authorization, Content-Type"])
    elseif !isempty(origin)
        return HTTP.Response(403,hs,JSON3.write(Dict("error"=>"Origin not allowed")))
    end
    reply(code,obj)=HTTP.Response(code,hs,JSON3.write(obj))
    req.target=="/health" && return reply(200,Dict("ok"=>true))
    req.target=="/api/expenses" || return reply(404,Dict("error"=>"Not found"))
    req.method=="OPTIONS" && return HTTP.Response(204,hs)
    req.method in ["GET","POST"] || return reply(405,Dict("error"=>"Method not allowed"))
    # Global rolling failure limit; no trust in caller-supplied proxy IP headers.
    limited=lock(gate) do
        times=get!(attempts,"auth",Float64[]); filter!(t->time()-t<60,times); length(times)>=30
    end
    limited && return reply(429,Dict("error"=>"Too many failed sign-ins. Wait one minute."))
    if !equalkey(HTTP.header(req,"Authorization",""),"Bearer "*KEY)
        lock(gate) do; push!(get!(attempts,"auth",Float64[]),time()); end
        return reply(401,Dict("error"=>"Incorrect app password"))
    end
    length(req.body)<=8192 || return reply(413,Dict("error"=>"Entry too large"))
    try
        if req.method=="GET"
            data,_=readledger(); return reply(200,data)
        end
        b=try JSON3.read(String(req.body),Dict{String,Any}) catch; return reply(400,Dict("error"=>"Invalid JSON")); end
        # Validate mutations before making a remote request.
        try
            action=get(b,"action","save")
            action=="save" ? valid(b) : (action in ["delete","check"] && get(b,"id",nothing) isa String || error("Invalid action"))
            action=="check" && !(get(b,"checked",nothing) isa Bool) && error("Invalid checkbox")
        catch
            return reply(400,Dict("error"=>"Invalid expense details"))
        end
        reply(200,writeledger(b))
    catch
        # Never log tokens, request bodies, GitHub responses, or passwords.
        reply(502,Dict("error"=>"GitHub is unavailable or configuration needs checking. Retry without closing your form."))
    end
end
if abspath(PROGRAM_FILE)==@__FILE__
    HTTP.serve(handler,"0.0.0.0",parse(Int,get(ENV,"PORT","8080"));verbose=false)
end
