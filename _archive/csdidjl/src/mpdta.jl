"""
    mpdta() → DataFrame

Load the Minimum‑Wage dataset from Callaway & Sant'Anna (2021).
500 counties × 5 years (2003–2007). Variables:

| Column        | Description                          |
|:------------- |:------------------------------------ |
| `year`        | Calendar year                        |
| `countyreal`  | County identifier                    |
| `lpop`        | Log population                       |
| `lemp`        | Log teen employment (outcome)        |
| `first_treat` | Year of first treatment (0 = never)  |
| `treat`       | Binary treatment indicator           |
"""
function mpdta()
    csv_path = joinpath(@__DIR__, "..", "data", "mpdta.csv")
    df = CSV.read(csv_path, DataFrame)
    # normalise column name for Julia conventions
    if "first.treat" in names(df)
        rename!(df, "first.treat" => "first_treat")
    end
    return df
end
