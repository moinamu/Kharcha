using Test
ENV["GITHUB_TOKEN"]="test-only"
ENV["GITHUB_REPO"]="owner/private-ledger"
ENV["APP_PASSWORD"]="test-only-password-24-characters"
ENV["ALLOWED_ORIGIN"]="https://owner.github.io"
include("../backend/server.jl")
@testset "Ledger operations without remote writes" begin
    d=Dict{String,Any}("entries"=>Any[])
    b=Dict{String,Any}("date"=>"2026-11-02","store"=>"Blinkit","category"=>"Grocery","note"=>"Milk","paise"=>12345)
    change!(d,b); @test length(d["entries"])==1
    id=d["entries"][1]["id"]
    change!(d,Dict("action"=>"check","id"=>id,"checked"=>true)); @test d["entries"][1]["checked"]
    b["id"]=id;b["paise"]=15050;change!(d,b)
    @test length(d["entries"])==1
    @test d["entries"][1]["paise"]==15050
    @test !d["entries"][1]["checked"]
    b["paise"]=-1;@test_throws Exception valid(b)
    @test equalkey("abc","abc") && !equalkey("abc","abd")
    change!(d,Dict("action"=>"delete","id"=>id)); @test isempty(d["entries"])
    @test handler(HTTP.Request("GET","/api/expenses")).status==401
    @test handler(HTTP.Request("GET","/api/expenses",["Origin"=>"https://wrong.example"])).status==403
    @test handler(HTTP.Request("OPTIONS","/api/expenses",["Origin"=>ENV["ALLOWED_ORIGIN"]])).status==204
end
