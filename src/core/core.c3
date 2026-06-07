module std::core::embedded;

macro @volatile_load(#x) @builtin
{
    return $$volatile_load(&#x);
}

macro @volatile_store(#x, value) @builtin
{
    return $$volatile_store(&#x, ($Typeof(#x))value);
}
