var pressedKeys = {
    shift: false,
    ctrl: false,
};
var ticksPerSecond = 1;

$(document).ready(function() {
    var $svg = $('#svg > svg:first');
    var svgHeight = $svg.attr('height');
    var svgWidth = $svg.attr('width');
    var $searchResultContainer = $svg.find('#search-results');
    var $baseChainText = $svg.find('g#chains > g:first').find('text:first');
    ticksPerSecond = cleanNumber($svg.data('ticks-per-second'));
    var $clickedGroup;

    $svg.find('g#chains > g')
        .mouseover(function(e) {
            var $group = $(this);
            if(!$group.find('title').size()) {
                var fullName = getGroupTitle($group, 1);
            }
            $('#hovered-sub').text($group.find('title:first').text());

        })
        .mouseout(function(e) {
            $('.extra-hovered').removeClass('extra-hovered');
            if($('#hovered-sub').text() === $(this).find('title:first').text()) {
                $('#hovered-sub').text('');
            }    
        })
        .click(function(e) {
            var $group = $(this);
            $clickedGroup = $group;
            var $rect = $group.find('rect:first');
            var $clickedText = $group.find('text:first');
            var svgWidth = $svg.attr('width');
            var fontWidth = $svg.data('font-width');

            var subName = getGroupTitle($group);

            // if the bottom bar is clicked -> nothing to fetch
            if(subName) {
                $.get($('#source-list').data('sub-source-url') + subName, function(data) {
                    $('#source-list').html(data);
                }).fail(function() {
                    $('#source-list').html('No source to show.');
                });
            }
            if(pressedKeys.shift && !pressedKeys.ctrl) {
                var cleanedSubName = subName.replace(/\[/g, '\\[');
                cleanedSubName = cleanedSubName.replace(/\]/g, '\\]');
                cleanedSubName = cleanedSubName.replace(/\//g, '\\/');
                $('#search').val('^' + cleanedSubName + '$');
                $('#search-form').submit();
                document.getSelection().removeAllRanges();
                return false;
            }
            else if(pressedKeys.ctrl && !pressedKeys.shift) {
                // Removes everything after the last ::
                var cleanedSubName = subName.substring(0, subName.length - subName.split('').reverse().join('').indexOf('::'));

                $('#search').val('^' + cleanedSubName);
                $('#search-form').submit();
                document.getSelection().removeAllRanges();
                return false;
            }

            $('.zoomed').removeClass('zoomed');
            $('.zoom-ancestor').removeClass('zoom-ancestor');
            $('.zoom-descendant').removeClass('zoom-descendant');
            $('.zoom-too-thin').removeClass('zoom-too-thin');

            // Most blobs are likely to be hidden so hide all first (but special-case the black bar)
            if($group.attr('id') !== 's-1') {
                $svg.find('g#chains > g').addClass('zoom-unwanted');
            }

            var oldOrigin = parseFloat($rect.data('orig-x') || $rect.attr('x'));
            var oldWidth = parseFloat($rect.data('orig-width') || $rect.attr('width'));
            var oldY = parseFloat($rect.attr('y'));

            changeChainAppearance($group, 0, svgWidth, fontWidth);
            $group.addClass('zoomed').removeClass('zoom-unwanted');

            // Find all descendants and make them a bit wider
            var wantedClass = $group.attr('id');
            $svg.find('g#chains > g.' + wantedClass).each(function() {
                var $foundGroup = $(this);
                var $foundRect = $foundGroup.find('rect:first');

                var foundX = parseFloat($foundRect.data('orig-x') || $foundRect.attr('x'));
                var foundWidth = parseFloat($foundRect.data('orig-width') || $foundRect.attr('width'));
                var foundY = parseFloat($foundRect.attr('y'));

                var newX = floatRound(svgWidth * ((foundX - oldOrigin) / oldWidth), 3);

                var newWidth = floatRound(svgWidth * (foundWidth / oldWidth), 3);
                changeChainAppearance($foundGroup, newX, newWidth, fontWidth);
                $foundGroup.addClass('zoom-descendant').removeClass('zoom-unwanted');
            });

            // make a '#list, #of, #ids' from classes starting with 's-'
            var ancestorIds = $group.attr('class')
                                    .split(/ +/)
                                    .filter((v) => 's-' === v.substring(0, 2))
                                    .map((v) => '#' + v)
                                    .join(', ');

            // Find all ancestors, but there are no ancestors for #s-1
            if($group.attr('id') !== 's-1') {
                $svg.find('g#chains > g').filter(ancestorIds).each(function() {
                    var $foundGroup = $(this);
                    changeChainAppearance($foundGroup, 0, svgWidth, fontWidth);
                    $foundGroup.addClass('zoom-ancestor').removeClass('zoom-unwanted');
                });
            }

            updateBaseChainText($group);
            $('#search-form').submit();
        });

    $('#search-reset').click(function(e) {
        $('#search-form').find('input').val('').end().submit();
    });
    $('#search-form').submit(function(e) {
        e.preventDefault();
        $searchResultContainer.empty();
        var searchString = $('#search').val();
        var searchRegex;
        if(searchString === '') {
            updateBaseChainText($clickedGroup);
            return;
        }
        var negativeSearch = searchString.substring(0, 1) === '!' ? 1 : 0;
        if(negativeSearch) {
            searchString = searchString.substring(1);
        }

        try {
            searchRegex = new RegExp(searchString);
        }
        catch(e) {
        }
        if(searchRegex) {
            var count = 0;
            var percent = 0;
            var checkCount = 0;
            var microSeconds = 0;
            var searchedUntilX = svgWidth;

            $svg.find('g#chains > g:not(.zoom-unwanted)').each(function() {
                var $group = $(this);
                var $title = $group.find('title:first');
                var $rect = $group.find('rect:first');

                // We have already found what we are searching for right of here
                if(parseFloat($rect.attr('x')) >= searchedUntilX) {
                    return true;
                }
                var fullName = getGroupTitle($group, 0);
                var searchMatches = fullName.match(searchRegex);

                if(searchMatches) {
                    $group.addClass('search-result');

                    var matchX = parseFloat($rect.attr('x'));
                    var matchWidth = parseFloat($rect.attr('width'));
                    searchedUntilX = matchX;
 
                    var percentText = $group.data('pc');
                    if(undefined !== percentText) {
                        percent += parseFloat(percentText);
                        microSeconds += cleanNumber($group.data('ms'));
                    }

                    var highligherClass = negativeSearch ? 'search-highlighter-unwanted' : 'search-highlighter';
                    var x = $rect.attr('width') < 1 ? $rect.attr('x') - 0.5 : $rect.attr('x');
                    var width = $rect.attr('width') < 1 ? 1 : $rect.attr('width');

                    addSearchHighlighter({
                        x: x,
                        width: width,
                        class: highligherClass,
                    });
                }
            });

            // negative search: mark all un-highlighted areas
            if(negativeSearch) {
                var previousX = $svg.attr('width');
                var allUnwanted = [];

                $searchResultContainer.find('.search-highlighter-unwanted').each(function() {
                    var $highlighter = $(this);
                    var highlightX = parseFloat($highlighter.attr('x'));
                    var highlightWidth = parseFloat($highlighter.attr('width'));
                    var highlightEnd = highlightX + highlightWidth;
                    allUnwanted.push({ x: highlightX, end: highlightEnd});

          //          if(highlightEnd < previousX) {
                        var negativeHighlighter = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
                        var distanceBetween = previousX - highlightEnd;

                        var x = distanceBetween < 1 ? distanceBetween - 0.5 : distanceBetween;
                        var width = distanceBetween < 1 ? 1 : distanceBetween;

                        addSearchHighlighter({
                            x: highlightEnd,
                            width: width,
                            class: 'search-highlighter',
                        });
             //       }
                    previousX = highlightX;
                });
                if(previousX > 0) {

                    addSearchHighlighter({
                        x: 0,
                        width: previousX,
                        class: 'search-highlighter',
                    });
                }
            }

            if(negativeSearch) {
                var shownMs = parseFloat(cleanNumber($clickedGroup ? $clickedGroup.data('ms') : $baseChainText.parent().data('ms')));
                updateBaseChainText($clickedGroup, shownMs - microSeconds, floatRound(100 - percent, 2), searchString, negativeSearch);
            }
            else {
                updateBaseChainText($clickedGroup, microSeconds, percent, searchString, negativeSearch);
            }
        }
    });

    $(document).keydown(function(e) {
            if(e.shiftKey) {
                pressedKeys['shift'] = true;
            }
            if(e.ctrlKey) {
                pressedKeys['ctrl'] = true;
            }
        })
        .keyup(function(e) {
            if(!e.shiftKey) {
                pressedKeys['shift'] = false;
            }
            if(!e.ctrlKey) {
                pressedKeys['ctrl'] = false;
            }
        });

    function updateBaseChainText($infoGroup, microSeconds, percent, searchString, isNegativeSearch) {
        if(!$infoGroup) {
            console.log('default group');
            $infoGroup = $baseChainText.parent();
        }
        var msAsNum = parseFloat(cleanNumber($infoGroup.data('ms')));
        var newText = 'showing: ' + $infoGroup.data('ms')+'ms (' + $infoGroup.data('pc') + '%)';
        if(undefined !== microSeconds) {
            var searchPercentOfShown = floatRound(100 * cleanNumber(microSeconds) / msAsNum, 2);
            microSeconds = formatNumber(microSeconds);
            var searchText = searchString ? '/' + searchString + '/' : '';
            searchText = isNegativeSearch ? '!' + searchText : searchText;
            newText = newText + ' of which ' + microSeconds + 'ms (' + floatRound(searchPercentOfShown, 2) + '%) matches ' + searchText;
        }
        $baseChainText.text(newText);
    }
    function addSearchHighlighter(settings) {
        var highlighter = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
        highlighter.setAttribute('x', floatRound(settings.x, 4));
        highlighter.setAttribute('y', 0);
        highlighter.setAttribute('width', floatRound(settings.width, 4));
        highlighter.setAttribute('height', svgHeight - 20);
        highlighter.setAttribute('class', settings.class);
        $searchResultContainer.get(0).appendChild(highlighter);
    }
});
function getGroupTitle($group, createElement) {
    var fullName = $group.data('name');

    if(fullName && !createElement) {
        return fullName;
    }

    // Build the name from possibly referred data
    // rns, ns | rsn, sn | rfn, fn | num
    var allData = $group.data();

    fullName = '';
    fullName = fullName + (allData.rns ? allData.rns : allData.ns  ? $('#' + allData.ns).data('rns') : '');

    // no use continuing without a name
    if(!fullName.length) {
        return '';
    }
    fullName = fullName + '::';
    fullName = fullName + (allData.rsn ? allData.rsn : allData.sn  ? $('#' + allData.sn).data('rsn') : '');

    if((allData.rfn || allData.fn) && allData.num) {
        fullName = fullName + '__ANON__[';
        fullName = fullName + (allData.rfn ? allData.rfn : allData.fn  ? $('#' + allData.fn).data('rfn') : '');
        fullName = fullName + ':' + allData.num + ']';
    }

    $group.data('name', fullName);

    if(createElement) {
        if(!$group.find('text:first').size()) {
            var textEl = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            textEl.setAttribute('y', parseFloat($group.find('rect:first').attr('y')) + 13);
            $group.get(0).appendChild(textEl);
        }
        if(!$group.find('title:first').size()) {
            var titleEl = document.createElementNS('http://www.w3.org/2000/svg', 'title');
            var percent = allData.pc;
            var ticks = cleanNumber(allData.t);

            var ms = formatNumber(floatRound(ticks / ticksPerSecond * 1000000, 0));
            var titleText = document.createTextNode(fullName + ' (' + ms + 'ms, ' + percent + '%)');
            titleEl.appendChild(titleText);
            $group.get(0).appendChild(titleEl);
        }
    }
    return fullName;
}
function formatNumber(number) {
    return ('' + number).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}
function cleanNumber(number) {
    try {
        return parseFloat(number.replace(/,/g, ''));
    }
    catch(e) {
        return number;
    }
}
function longestPossibleText(text, width, fontWidth) {

    var maxTextLength = Math.floor(width / fontWidth);
    return text.length > maxTextLength ? maxTextLength >= 3 ? text.substr(0, maxTextLength - 1) + '…'
                                       :                      ''
         :                               text
         ;
}
function floatRound(number, precision) {
    return Number(Math.round(number + 'e' + precision) + 'e-' + precision);
}

function changeChainAppearance($group, newX, newWidth, fontWidth) {
    var $rect = $group.find('rect:first');
    var $text = $group.find('text:first');

    if(!$rect.data('orig-x')) {
        $rect.attr('data-orig-x', $rect.attr('x'));
        $rect.attr('data-orig-width', $rect.attr('width'));
    }

    $rect.attr('x', newX)
         .attr('width', newWidth);

    var title = longestPossibleText(getGroupTitle($group, 0), $rect.attr('width'), fontWidth);

    if(title) {
        if(!$group.find('text:first').size()) {
            getGroupTitle($group, 1);
        }
        $text = $group.find('text:first');
        $text.attr('x', newX + 2.5);
        $text.text(title);
    }
    else if($text.size()) {
        $text.text('');
    }
    if($rect.attr('width') < 0.3) { $group.addClass('zoom-too-thin'); }

    $group.addClass('zoom-descendant');
}
