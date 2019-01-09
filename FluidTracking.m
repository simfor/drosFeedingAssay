%Wolf 2018 - B 01/04/2019
%Tracks fluid flow from capillaries.

%Simple summary: User to crop out section containing only
%capillaries and base and then cut out the base. After that, the script 
%creates rectangles around each capillary tube by checking for minimum length and circularity.
%After identifying rectangles surrounding capillaries, we iterate over
%each rectangle and identify regions, filter them by length, and log the appropriate lengths to the output.


%Usage: First, drag rectangle over area only containing capillaries and
%base
%Next, crop out the base and white portions and allow it to run

%Note: Post processing is neccessary, you need to remove any spontaneous
%drops. An easy way to do this is to remove any movements of great than
%some percent. E.g. don't count movements if they're greater than 5 of
%previous size. This, of course, should be dependent on setup.

%Pay close attention to the sorting method

function main()

    %Establish global vars for tracking in other functions
    global frameNumber;
    global output;
    global sortedRects;
    global masterRect;
    sortedRects = {};
    masterRect = {};
    frameNumber = 1;
    output = [,];
    
    v = VideoReader('Data/12_21.avi'); 
    
    %Start time here in this case we start at 5 minutes to avoid any
    %movement associated with starting the videos
    v.CurrentTime = 300;
    while v.CurrentTime < v.Duration
        vidFrame = readFrame(v);
        im = vidFrame;
        if v.CurrentTime < 301
            
            %It may be necessary to implement this filtering depending on the video source
            %im = imgaussfilt(im, 1);
            
            %Get's a set of rectangles to look for hue in later. We only
            %search in original rectangles to avoid appearance of movement
            %outside of original location
            
            [masterRect,maskedRGBImage,rect,pos] = AnalyzeImageRects(im, 60, 6, 2); 
        end
        
        im = imgaussfilt(im, 1);
        
        %Crop rectangle manually selected in AnalyzeImageRects
        I = imcrop(im, masterRect);  
        
        %Convert to black and white using filter -- note that it is not necessarily the same filter as AnalyzeImageRect
        I = convBW(I); 
        
        %Crop out the base to stop misidentifcation of base liens as capillaries 
        I(round(pos(1,2)):round(pos(1,2)+pos(1,4)),round(pos(1,1)):round(pos(1,1)+pos(1,3)))=0;
        
        
        %Update output -- note that sorting can cause an issue.
        AnalyzeImage(I, 60, 6, 2, sortedRects);
        
        %Move 2 minutes between each analysis
        if v.CurrentTime < v.Duration - 120
            v.CurrentTime = v.CurrentTime + 120;
        else
            v.CurrentTime = v.Duration;
        end
    end

    csvwrite('test.csv',output)
end

function AnalyzeImage(BW, minLength, rowCount, colCount, rectangles)
    global output;
    global frameNumber;
    count = 0;
    
    BW = imfill(BW,'holes');

    %TODO: Use circularity to check as well, possibly implementing regionprops.
    for i = 1:length(rectangles)
        %Crop to appropriate rectangle from masterRects
        tem = imcrop(BW, rectangles{i});
        tem = imfill(tem,'holes');
        %imshow(tem);
        [temB,temL] = bwboundaries(tem,'noholes');
        %Image cleaning
        stats = regionprops(temL,'Area','Centroid','BoundingBox');
        for k = 1:length(temB)
            boxLength = max(stats(k).BoundingBox(3:4));
            if boxLength > minLength 
                count = count + 1;
                output(frameNumber, count) = boxLength;
            end
        end
    end
    if count ~= rowCount*colCount
        fprintf("More or less than rowCount*colCount capillaries being tracked. Likely causing tracking to be out of order");
    end

    frameNumber = frameNumber + 1;
end

function [masterRect,maskedRGBImage,rect,pos] = AnalyzeImageRects(I, distMin, rowCount, colCount)
    global frameNumber;
    global sortedRects;
    rects = {};
    count = 0;

    %Note that it may be worthwhile to implement imabsdiff here to adjust
    %things
    % read the original image and put a gaussian filter to smooth
    %I = imgaussfilt(I, 2);
    % call createMask function to get the mask and the filtered image
    [BW,maskedRGBImage,rect,pos] = createMask(I);
    masterRect = rect;
    BW = imfill(BW,'holes');

    %TODO: Use circularity to check as well, possibly implementing regionprops.
    [B,L] = bwboundaries(BW,'noholes');
    stats = regionprops(L,'Area','Centroid','BoundingBox');
    

    for k = 1:length(B)
        boundary = B{k};
        maxCircularity = 1.5; %Circularity solution

        boxLength = max(stats(k).BoundingBox(3:4));

        %Consider using 'BoundingBox'
        delta_sq = diff(boundary).^2;
        perimeter = sum(sqrt(sum(delta_sq,2)));
        area = stats(k).Area;
        % compute the roundness metric - ad hoc solution
        metric = 4*pi*area/perimeter^2;

        shouldPlot = false;
        if boxLength > distMin && metric < maxCircularity
            shouldPlot = true;
        end
        if shouldPlot == true
            count = count + 1;
            rects{count} = stats(k).BoundingBox;
        end
    end
    
    %Sorting
    mat = cell2mat(rects');
    
    sort = sortrows(mat,1);
    sort2 = sortrows(sort(1:5,:), 2);
    sort3 = sortrows(sort(6:size(sort,1),:), 2); %WEird numbers due to missing single capillary.
    
    sort2 = sort2';
    sort3 = sort3';
                   
    for k = 1:(size(sort,1)) %Basic sorting -- needs fixing
                   
        if k < 6 
            sortedRects{k} = sort2(:,k);
        else
            sortedRects{k} = sort3(:,k-5);
        end
    end

    if count ~= rowCount*colCount
        fprintf("More or less than rowCount*colCount capillaries being tracked. Likely causing tracking to be out of order");
    end

    frameNumber = frameNumber + 1;
end


function [BW,maskedRGBImage,rect,pos] = createMask(RGB) %Most of this code is leftover from color dependent tracking
    % Convert RGB image to HSV image
     I = rgb2hsv(RGB);
    % Define thresholds for 'Hue'. Modify these values to filter out different range of colors.
    channel1Min =0;
    channel1Max = 0;
    % Define thresholds for 'Saturation'
    channel2Min = 0;
    channel2Max = 0;
    % Define thresholds for 'Value' -- In this case gray value from 20 to
    % 50% -- It's likely we should make this a parameter
    channel3Min = .2;
    channel3Max = .50;
    % Create mask based on chosen histogram thresholds
    BW = ( (I(:,:,1) >= channel1Min) | (I(:,:,1) <= channel1Max) ) & ...
        (I(:,:,2) >= channel2Min ) & (I(:,:,2) <= channel2Max) & ...
        (I(:,:,3) >= channel3Min ) & (I(:,:,3) <= channel3Max);
    BW = imfill(BW, 'holes');    
    [BW, rect] = imcrop(BW);
    imshow(BW)
    H=imrect(gca);
    pos=wait(H);
    close all
    BW(pos(1,2):pos(1,2)+pos(1,4),pos(1,1):pos(1,1)+pos(1,3))=0;
    maskedRGBImage = imcrop(RGB, rect);
    maskedRGBImage(pos(1,2):pos(1,2)+pos(1,4),pos(1,1):pos(1,1)+pos(1,3))=0;
    maskedRGBImage(repmat(~BW,[1 1 3])) = 0;
end

                   
%Simple convert and fill
function BW = convBW(RGB)
    I = rgb2hsv(RGB);
    % Define thresholds for 'Hue'. Modify these values to filter out different range of colors.
    channel1Min =0;
    channel1Max = 0;
    % Define thresholds for 'Saturation'
    channel2Min = 0;
    channel2Max = 0;
    % Define thresholds for 'Value' -- In this case gray value from 10 to
    % 50% -- It's likely we should make this a parameter
    channel3Min = .1;
    channel3Max = .5;
    % Create mask based on chosen histogram thresholds
    BW = ( (I(:,:,1) >= channel1Min) | (I(:,:,1) <= channel1Max) ) & ...
        (I(:,:,2) >= channel2Min ) & (I(:,:,2) <= channel2Max) & ...
        (I(:,:,3) >= channel3Min ) & (I(:,:,3) <= channel3Max);
    BW = imfill(BW, 'holes');
end
