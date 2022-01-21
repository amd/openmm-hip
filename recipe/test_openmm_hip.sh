#!/bin/bash
set +ex

summary=""; exitcode=0; count=0;
for f in TestHip*; do
    ((count+=1))
    echo -e "\n#$count: $f"
    # Retry three times so stochastic tests have a chance
    attempts=0
    while true; do
        ./${f} $@
        thisexitcode=$?
        ((attempts+=1))
        if [[ $thisexitcode == 0 || $attempts == 3 ]]; then break; fi
    done
    if [[ $thisexitcode != 0 ]]; then summary+="\n#$count ${f}"; fi
    ((exitcode+=$thisexitcode))
done
if [[ $exitcode != 0 ]]; then
    echo "------------"
    echo "Failed tests"
    echo "------------"
    echo -e "${summary}"
    exit $exitcode
else
    echo "----------------"
    echo "All tests passed"
    echo "----------------"
fi
