FROM julia:1.10
WORKDIR /app
COPY Project.toml ./
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
COPY server.jl ./
ENV PORT=8080
EXPOSE 8080
CMD ["julia", "--project=.", "server.jl"]
