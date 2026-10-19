# hopr cds to the repo root; hopw to the configured workspace holding $PWD, the longest one when two nest.
function hopr --description 'cd to the repo root'
	hop /
end

function hopw --description 'cd to the workspace holding $PWD'
	hop __hopw
end
