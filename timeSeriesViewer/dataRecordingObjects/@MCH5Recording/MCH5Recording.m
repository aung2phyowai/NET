classdef MCH5Recording < dataRecording
  %MCH5Recording Reads a h5 recording file exported by MCS DataManager.
  % This class is used to read h5 containing raw data and
  % trigger information (currently from digital in data) from a 
  % MultiChannelSystems h5 file exported by MultiChannel DataManager.
  % .h5 file specification can be found in the link:
  % https://mcspydatatools.readthedocs.io/en/latest/mcs_hdf5_protocol.html

  % AUTHOR: stefano.masneri@brain.mpg.de & Mark Shein-Idelson
  % DATE: 18.04.2017
  % 
  % TODO:
  %   - See how multiple recoding in a single h5 file works
  %   - Set up protocol for using triggers (i.e. digital events) instead of
  %   using get_triggers_from_digin. Maybe use check flag as "digital_events=1" for when
  %   it is set up vs "digital_events=0" for when we have to calc from dig in
  
  properties
    numRecordings;   % number of recordings in a single .h5 file. Currently only supports 1
    timestamps;      % timestamps information for each channel
%     triggerFilename; % name of the *.kwe file containing trigger info
    digital_events=0;
%     bitDepth;        % number of bits used to store data
    sample_ms;
    fullFilename;    % path + name
    recNameHD5;  % names of all recordings
    dataLength;      % total samples in the data
    totalChannels    % total channels in the data
    info;            % information on recording file
    analogInfo       % information on the analog stream of first recording
    lengthInfo;      % information on recording file length
%     globalStartTime  % start time within the session
    streamPaths      % paths to streams
    streamsSubTypes  % type pf streams (electrode, aux, digital)
    electrodeStreamNum %the stream number in h5 file containing raw electrode data (usually 0)
    auxStreamNum
    digitalStreamNum
    pathToRawDataStreamGroup
    pathToDigitalDataStreamGroup
    pathToAuxDataStreamGroup
    electrodeInfoChannel
%     digitalInfoChannel
%     auxInfoChannel
    unit %Physical unit of the measured sensor value
    exponent %1xn
    numOfChannels=252 %number of elecroeds in the MEA
    analogThreshold=-330; %analog photodiode flip indicator
    analogUpLowRange=-315;
    analogUpHighRange=-290;
    analogDownHighRange=-350;
    analogDownLowRange=-370;
    includeOnlyDigitalDataInTriggers=0; %this is to make frameTimeFromDiode.m to work
  end
  
   properties (Constant, Hidden)
        defaultRawDataStreamName='Electrode';
        defaultFilteredDataStreamName='Filtere';
        defaultAnalogDataStreamName='Auxiliary';
        defaultTriggerStreamName='Trigger'; %CHANGE THIS TO EVENTS
        defaultDigitalDataStreamName='Digital';
%         fileExtension='h5';
        pathToAllRecordings='/Data/';
        pathToRecording='/Data/Recording_0/';
        pathToAnalogStream = '/Data/Recording_0/AnalogStream/'; %This is in case there is only one recording in HDF5 file. If there are more - code should be revised
        maxNumberOfDigitalChannels=16; %up to 16 digIn channels
   end
    
  properties (Constant = true)
    
    
%     pathToTriggerData = '/event_types/TTL/events/time_samples'; % where the triggers are stored in the .kwe file
%     pathToTriggerOnOff = '/event_types/TTL/events/user_data/eventID';
%     pathToTriggerChannel = '/event_types/TTL/events/user_data/event_channels';
        
    %must define them, bc abstract in base class
    defaultLocalDir='E:\Yuval\DataAnalysis'; %Default directory from which search starts
    signalBits = 24 %the quantization of the sampling card
    numberOfCharFromEndToBaseName=7;
  end
  
  methods
    
    function [V_uV ,t_ms]=getData(obj, channels, startTime_ms, window_ms)
      %GETDATA Extract MCS h5 recording data from file to memory
      %Usage: [V_uV,t_ms] = obj.getData(channels,startTime_ms,window_ms);
      %Input : channels - [1xN] a vector with channel numbers as appearing in the data folder files
      %        startTime_ms - a vector [1xN] of start times [ms]. If Inf, returns all time stamps in recording (startTime_ms is not considered)
      %        window_ms - a scalar [1x1] with the window duration [ms].
      %Output: V_uv - A 3D matrix [nChannels x nTrials x nSamples] with voltage waveforms across specified channels and trials
      %        t_ms - A time vector relative to recording start (t=0 at start)
      
      windowSamples = double(round(double(window_ms) / obj.sample_ms(1)));
      nWindows = numel(startTime_ms);
      startTime_ms = round(startTime_ms/obj.sample_ms(1))*obj.sample_ms(1);
      startElement = double(round(startTime_ms/obj.sample_ms(1)));
      if startElement(1) == 0 || Inf == startElement(1)
        startElement(1) = 1;
      end
      %window_ms = windowSamples * obj.sample_ms(1);
      
      if isempty(channels) %if no channels are entered, get all channels
%         channels=obj.channelNumbers;
        channels=1:obj.numOfChannels;
      end
      
      nCh = numel(channels);
      allChannels=nCh==obj.numOfChannels;
     
      if ~allChannels %If all channels were selected, retrieve all and sort n2s afterwards
        channels=obj.n2s(channels); %check with mark
      end
      
      V_uV = zeros(nCh, nWindows, windowSamples, obj.datatype); %initialize waveform matrix
      %{
      	YUVAL: I have switched between channel/samples indices because for
      	some reason the data matrix is fliped here (i.e. when loading the
      	whole data into a matrix we get samplesXchannels matrix instead of
      	a channelsXsamples matrix.
        So check to see if this really works and/or if is consistent with
        larger datasets
        I have also transposed the h5read returned matrix so the V_uV will
        be in a channels/samples order.
        So the original line was 
        V_uV(k, m, :) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
                [channels(k) startElement(m)], [1 windowSamples]);
        and it was changed to
      V_uV(k, m, :) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
                [startElement(m) channels(k)], [windowSamples 1])'; 
        (notice the transposition at the end)
      
      %}
      % Speed up if all channels are consecutives
      if all(diff(channels)==1) || allChannels 
        for m = 1:numel(startElement)
          if startElement(m) <= -windowSamples
            %do nothing, return all zeros
          elseif startElement(m) < 1
            V_uV(:, m, -startElement(m)+1 : end) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
              [1 channels(1)], [windowSamples + startElement(m) length(channels)])';
          elseif startElement(m) >= obj.dataLength
            startElement(m) = obj.dataLength - windowSamples;
            V_uV(:, m, :) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
              [startElement(m) channels(1)], [windowSamples length(channels)])';
          elseif startElement(m) + windowSamples > obj.dataLength
            V_uV(:, m, 1:obj.dataLength-startElement(m)) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
              [startElement(m) channels(1)], [obj.dataLength - startElement(m) length(channels)])';
          else
            V_uV(:, m, :) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
              [startElement(m) channels(1)], [windowSamples length(channels)])';
          end
        end
      else
        for k = 1:length(channels)
          for m = 1:numel(startElement)

            if startElement(m) <= -windowSamples
              %do nothing, return all zeros
            elseif startElement(m) < 1
              V_uV(k, m, -startElement(m)+1 : end) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
                [1 channels(k)], [windowSamples + startElement(m) 1])';
            elseif startElement(m) >= obj.dataLength
              startElement(m) = obj.dataLength - windowSamples;
              V_uV(k, m, :) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
                [startElement(m) channels(k)], [windowSamples 1])';
            elseif startElement(m) + windowSamples > obj.dataLength
              V_uV(k, m, 1:obj.dataLength-startElement(m)) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
                [startElement(m) channels(k)], [obj.dataLength - startElement(m) 1])';
            else
              V_uV(k, m, :) = h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData'], ...
                [startElement(m) channels(k)], [windowSamples 1])';
            end
          end
        end
      end
      
      if allChannels
         tempChannels=zeros(size(V_uV));
         for i=1:nCh
            tempChannels(i,:,:)=V_uV(obj.n2s(i),:,:); 
         end
         V_uV=tempChannels;
        clear tempChannles
      end
      
      
      if obj.convertData2Double
          V_uV=double(V_uV);
          for k = 1:size(V_uV, 1)
              V_uV(k, :, :) = (V_uV(k, :, :)-obj.ZeroADValue(k)) * obj.MicrovoltsPerAD(k)*(10^(double(obj.exponent(k))+6)); %exponent brings value in V, we want uV
          end
      end
      
      if nargout==2
        t_ms=(1:windowSamples)*(1e3/obj.samplingFrequency(1));
      end

    end
    

     function [V_uV,T_ms]=getAnalogData(obj,channels,startTime_ms,window_ms,name)
            %Extract MCRack recording analog data. For now only supports
            %the data from auxillary stream, so 'name' and 'Channels' has no function here.
            %Usage: [V_uV,T_ms]=obj.getAnalogData(channels,startTime_ms,window_ms,name);
            %Input : channels - [1xN] a vector with channel numbers as appearing in the data folder files
            %        startTime_ms - a vector [1xN] of start times [ms]. If Inf, returns all time stamps in recording (startTime_ms is not considered)
            %        window_ms - a scalar [1x1] with the window duration [ms].
            %        name - the name of the stream (if not entered, default name is used)
            %Output: V_us - A 3D matrix [nChannels x nTrials x nSamples] with voltage waveforms across specified channels and trials
            %        T_ms - A time vector relative to recording start (t=0 at start)
            
            %obj.analogDataStreamNumber=find( cellfun(@(x) all(x(1:numel(obj.defaultAnalogDataStreamName))==obj.defaultAnalogDataStreamName),obj.streamNames) );
                %obj.analogDataInfo
%{
            if nargin==4
                obj.getDataConfig.streamname=obj.streamNames{obj.analogDataStreamNumber};
            elseif nargin==5
            %Yuval: see if something should be done here...    
                
%                 obj.getDataConfig.streamname=name;
%                 %this option should be revised because currently all parameters are derived from the raw data stream
            else
                error('method getAnalogData was not used correctly: wrong number of inputs');
            end
            if isempty(channels)
                channels=obj.analogChannelNumbers;
            end
            conversionFactor=1/obj.sample_ms;
            startTime_ms=round(startTime_ms*conversionFactor)/conversionFactor;
            window_ms=round(window_ms*conversionFactor)/conversionFactor;
            endTime_ms=startTime_ms+window_ms; %no need to conversion factor
            recordingDuration_ms=round(obj.recordingDuration_ms*conversionFactor)/conversionFactor;
            windowSamples=round(window_ms*conversionFactor);
            nTrials=length(startTime_ms);
            V_uV=ones(numel(channels),nTrials,windowSamples,'uint16')*obj.ZeroADValueAnalog;
            
            cumStart=[-Inf obj.cumStart obj.cumEnd(end)];
            cumEnd=[0 obj.cumEnd Inf];
            obj.getDataConfig.StreamNumber=obj.analogDataStreamNumber-1;
            if obj.multifileMode %this mode currently does not support extraction from edges of the recording
                for i=1:nTrials
                    tmpStartTime=startTime_ms(i);
                    startSample=1;
                    
                    pFileStart=find(startTime_ms(i)>=cumStart,1,'last');
                    pFileEnd=find((startTime_ms(i)+window_ms)<=cumEnd,1,'first');
                    
                    for f=pFileStart:pFileEnd
                        tmpEndTime=min([cumEnd(f) endTime_ms(i)]);
                        endSample=round(startSample+(tmpEndTime-tmpStartTime)/1000*obj.samplingFrequency)-1;
                        
                        if f>1 && f<=(obj.nRecordings+1) % data in inside recording range
                            mcstreammex(obj.fileOpenStruct(f-1));
                            obj.getDataConfig.startend=[tmpStartTime;tmpEndTime]-cumStart(f);
                            data=mcstreammex(obj.getDataConfig);
                            data=reshape(data.data,obj.totalAnalogChannels,length(data.data)/obj.totalAnalogChannels);
                            V_uV(:,i,startSample:endSample)=data(channels,:);
                        else % some of the data is outside the recording range - add zeros
                            V_uV(:,i,startSample:endSample)=obj.ZeroADValueAnalog;
                        end
                        startSample=endSample+1;
                        tmpStartTime=tmpEndTime;
                    end
                end
            else
                for i=1:nTrials
                    obj.getDataConfig.startend=[startTime_ms(i);startTime_ms(i)+window_ms];
                    if startTime_ms(i)>=0 && (startTime_ms(i)+window_ms)<=recordingDuration_ms
                        data=mcstreammex(obj.getDataConfig);
                        data=reshape(data.data,obj.totalAnalogChannels,length(data.data)/obj.totalAnalogChannels);
                        V_uV(:,i,:)=data(channels,:);
                    else
                        startSample=min(0,round(startTime_ms(i)*conversionFactor));
                        endSample=min(windowSamples,round((recordingDuration_ms-startTime_ms(i))*conversionFactor)); %end sample in window (not in recroding)
                        obj.getDataConfig.startend=[max(0,startTime_ms(i));min(startTime_ms(i)+window_ms,recordingDuration_ms)];
                        data=mcstreammex(obj.getDataConfig);
                        data=reshape(data.data,obj.totalAnalogChannels,length(data.data)/obj.totalAnalogChannels);
                        V_uV(:,i,1-startSample:endSample)=data(obj.number2ID(channels),:);
                        disp('Recording at edge');
                    end
                end
            end
            if obj.convertData2Double
                V_uV = (double(V_uV) - obj.ZeroADValueAnalog) * obj.MicrovoltsPerADAnalog;
            end
            
        if nargout==2
                T_ms=(1:windowSamples)*(1e3/obj.samplingFrequency);
            end
    %}
               
        if nargin==2
            startTime_ms=0;
            window_ms=obj.recordingDuration_ms;
        elseif nargin~=4 && nargin~=5
            error('method getAnalogData was not used correctly: wrong number of inputs');
        end
        windowSamples = double(round(double(window_ms) / obj.sample_ms(1)));
        nWindows = numel(startTime_ms);
        startTime_ms = round(startTime_ms/obj.sample_ms(1))*obj.sample_ms(1);
        startElement = double(round(startTime_ms/obj.sample_ms(1)));
        if startElement(1) == 0 || Inf == startElement(1)
            startElement(1) = 1;
        end
        
        V_uV = zeros(nWindows, windowSamples, obj.datatype); %initialize waveform matrix
        for m = 1:numel(startElement)
          if startElement(m) <= -windowSamples
            %do nothing, return all zeros
          elseif startElement(m) < 1
            V_uV(m, -startElement(m)+1 : end) = h5read(obj.fullFilename, [obj.pathToAuxDataStreamGroup '/ChannelData'], ...
              [1 1], [windowSamples + startElement(m) 1])';
          elseif startElement(m) >= obj.dataLength
            startElement(m) = obj.dataLength - windowSamples;
            V_uV(m, :) = h5read(obj.fullFilename, [obj.pathToAuxDataStreamGroup '/ChannelData'], ...
              [startElement(m) 1], [windowSamples 1])';
          elseif startElement(m) + windowSamples > obj.dataLength
            V_uV(m, 1:obj.dataLength-startElement(m)) = h5read(obj.fullFilename, [obj.pathToAuxDataStreamGroup '/ChannelData'], ...
              [startElement(m) 1], [obj.dataLength - startElement(m) 1])';
          else
            V_uV(m, :) = h5read(obj.fullFilename, [obj.pathToAuxDataStreamGroup '/ChannelData'], ...
              [startElement(m) 1], [windowSamples 1])';
          end
        end
%         [99540459]
        if obj.convertData2Double
            V_uV=double(V_uV);
            for k = 1:size(V_uV, 1)
                V_uV(k, :, :) = (V_uV(k, :, :)-obj.ZeroADValue(k)) * obj.MicrovoltsPerAD(k)*(10^(double(obj.exponent(k))+6)); %exponent brings value in V, we want uV
            end
        end

        if nargout==2
            T_ms=(1:windowSamples)*(1e3/obj.samplingFrequency(1));
        end
    end
    
    function [D,T_ms]=getDigitalData(obj,startTime_ms,window_ms)
        %Extract MC digital data from recording from h5 file
        %Usage: [D,T_ms]=getDigitalData(startTime_ms,window_ms)
        %Input : startTime_ms - a vector [1xN] of start times [ms]. If Inf, returns all time stamps in recording (startTime_ms is not considered)
        %        window_ms - a scalar [1x1] with the window duration [ms].
        %        name - the name of the stream (if not entered, default name is used)
        %Output: D - A 3D matrix [nChannels x nTrials x nSamples] with digitalData waveforms across specified channels and trials
        %        T_ms - A time vector relative to recording start (t=0 at start)
        if nargin==1
            startTime_ms=0;
            window_ms=obj.recordingDuration_ms;
        elseif nargin~=3
            error('method getDigitalData was not used correctly: wrong number of inputs');
        end
        windowSamples = double(round(double(window_ms) / obj.sample_ms(1)));
        nWindows = numel(startTime_ms);
        startTime_ms = round(startTime_ms/obj.sample_ms(1))*obj.sample_ms(1);
        startElement = double(round(startTime_ms/obj.sample_ms(1)));
        if startElement(1) == 0 || Inf == startElement(1)
            startElement(1) = 1;
        end
        
%         conversionFactor=1/obj.sample_ms; %sapmleNum=time*conversion factor (?)
%         startTime_ms=round(startTime_ms*conversionFactor)/conversionFactor;
%         window_ms=round(window_ms*conversionFactor)/conversionFactor;
%         endTime_ms=startTime_ms+window_ms; %no need to conversion factor
%         recordingDuration_ms=round(obj.recordingDuration_ms*conversionFactor)/conversionFactor;
%         windowSamples=round(window_ms*conversionFactor);

        D=false(obj.maxNumberOfDigitalChannels,nWindows,windowSamples); %up to 16 digital bits are allowed

%         obj.getDataConfig.StreamNumber=obj.digitalDataStreamNumber-1;
%         if obj.multifileMode %Currently Not Supported
%             for i=1:nWindows
%                 pFileStart=find(startTime_ms(i)>=obj.cumStart,1,'last');
%                 pFileEnd=find((startTime_ms(i)+window_ms)<=obj.cumEnd,1,'first');
%                 tmpStartTime=startTime_ms(i);
%                 startSample=1;
%                 for f=pFileStart:pFileEnd
%                     mcstreammex(obj.fileOpenStruct(f));
% 
%                     tmpEndTime=min([obj.cumEnd(f) endTime_ms(i)]);
%                     obj.getDataConfig.startend=[tmpStartTime;tmpEndTime]-obj.cumStart(f);
% 
%                     if tmpStartTime>=0 && tmpEndTime<=recordingDuration_ms
%                         data=mcstreammex(obj.getDataConfig);
%                         endSample=startSample+numel(data.data)-1;
%                         D(:,i,startSample:endSample)=rem(floor(data.data*pow2(0:-1:(1-obj.maxNumberOfDigitalChannels))),2)';
%                     else
%                         error('Requested data is outside stream limits - this is currently not supported in multi file mode');
%                     end
%                     startSample=endSample+1;
%                     tmpStartTime=tmpEndTime;
%                 end
%             end
%         else %single file mode
            for i=1:nWindows
%                 obj.getDataConfig.startend=[startTime_ms(i);startTime_ms(i)+window_ms];
%                 startSample=min(0,round(startTime_ms(i)*conversionFactor))+1;
                if startTime_ms(i)>=0 && (startTime_ms(i)+window_ms)<=obj.recordingDuration_ms
                    data=h5read(obj.fullFilename,[obj.pathToDigitalDataStreamGroup '/ChannelData'],...
                       [startElement(i) 1], [windowSamples 1] );
                    D(:,i,:)=rem(floor(double(data)*pow2(0:-1:(1-obj.maxNumberOfDigitalChannels))),2)';
                else
                    windowSamples=min(windowSamples,obj.dataLength-startElement(i));
%                     obj.getDataConfig.startend=[max(0,startTime_ms(i));min(startTime_ms(i)+window_ms,recordingDuration_ms)];
%                     data=mcstreammex(obj.getDataConfig);
                    data=h5read(obj.fullFilename,[obj.pathToDigitalDataStreamGroup '/ChannelData'],...
                       [startElement(i) 1], [windowSamples 1] );
                    D(:,i,1-startSample:endSample)=rem(floor(data.data*pow2(0:-1:(1-obj.maxNumberOfDigitalChannels))),2)';
                    disp('Recording at edge');
                end
            end
%         end
        if nargout==2
            T_ms=(1:windowSamples)*(1e3/obj.samplingFrequency);
        end
    end
    
     function [T_ms]=getTrigger(obj,startTime_ms,window_ms,bits)
        %Extract triggers from digital in. Currently does not support
        %events from MC Recorder.
        %Usage : [T_ms]=obj.getTrigger(startTime_ms,window_ms,bits)
        %Input : startTime_ms - start time [ms].
        %        window_ms - the window duration [ms]. If Inf, returns all time stamps in recording (startTime_ms is not considered)
        %        bits - array of the bits to which triggers should be
        %        calculated (up to obj.maxNumberOfDigitalChannels). [1 2 4]
        %        listens to bits 1,2,4
        %Output: T_ms - trigger times [ms] - different triggers are arranged in a cell array
        
        if nargin==4
            [D,Ttmp]=getDigitalData(obj,startTime_ms,window_ms);
        elseif nargin==3
            [D,Ttmp]=getDigitalData(obj,startTime_ms,window_ms);
            bits=1:obj.maxNumberOfDigitalChannels;
        elseif nargin==1
            startTime_ms=0;
            window_ms=obj.recordingDuration_ms;
            [D,Ttmp]=getDigitalData(obj,startTime_ms,window_ms);
            bits=1:obj.maxNumberOfDigitalChannels;
        end
        nbits=numel(bits);
        nTriggersDigital=2*nbits;
%         T=cell(nTriggersDigital,nFiles);
        T=cell(nTriggersDigital,1);

        for j=1:nbits
            T{2*j-1,1}=Ttmp(find(diff(squeeze(D(bits(j),:,:)))>0));%+obj.cumStart(i);
            T{2*j,1}=Ttmp(find(diff(squeeze(D(bits(j),:,:)))<0));%+obj.cumStart(i);
        end
        
        
        for i=1:nTriggersDigital
            T_ms{i}=cell2mat(T(i,:));
        end
        %T_ms(cellfun(@isempty,T_ms))=[];

    end

%     function [T_ms]=getAnalogFlips(obj,startTime_ms,window_ms)
%      %Extract flip Times from Auxillary photodiode stream. 
%      %Usage : [T_ms]=obj.getAnalogTrigger(startTime_ms,window_ms)
%      %Input : startTime_ms - start time [ms].
%      %        window_ms - the window duration [ms]. If Inf, returns all time stamps in recording (startTime_ms is not considered)
%      %Output: T_ms - times of flips [ms]
%       if nargin==3
%             [A,Ttmp]=getAnalogData(obj,startTime_ms,window_ms);
%         elseif nargin==1
%             startTime_ms=0;
%             window_ms=obj.recordingDuration_ms;
%             [A,Ttmp]=getAnalogData(obj,startTime_ms,window_ms);
%       else
%              error('method getAnalogTriggers was not used correctly: wrong number of inputs');
%       end
%       logicUps=A>obj.analogUpLowRange & A<obj.analogUpHighRange;
%       logicDowns=A>obj.analogDownLowRange & A<obj.analogDownHighRange;
% %       logicDowns=A<obj.analogThreshold;
%       T_ms=Ttmp(find(diff(logicDowns)~=0));
%         
%   
%     end
  end
  
  methods (Hidden = true)
    
    %class constructor
    function obj = MCH5Recording(recordingFile)
      %get data files
      if nargin == 0
        recordingFile=[];
      elseif nargin>1
        disp('MCH5Recording: Object was not constructed since too many parameters were given at construction');
        return;
      end

      obj = obj.getRecordingFiles(recordingFile, 'h5');
      
      % Find the .h5 file
      %[~, name, ~] = fileparts(obj.recordingName);
      obj.fullFilename = fullfile(obj.recordingDir, obj.recordingName);
      filePrefix=strsplit(obj.recordingName,'_');
      
%       %%%YUVAL: CHANGE TO GET RELEVANT TRIGGER PROPERTIES FROM HDF5 %%%%%
%       triggerFile = dir([obj.recordingDir filesep filePrefix{1} '*.kwe']);
%       if isempty(triggerFile)
%           triggerFile = dir([obj.recordingDir filesep '*.kwe']);
%           disp(['Trigger file with prefix ' filePrefix{1} ' not found!!!!, looking for other .kwe files in the same folder']);
%       end
%       if isempty(triggerFile)
%         error('KwikRecording: Cannot file .kwe file')
%       elseif length(triggerFile) > 1
%         warning('KwikRecording: Multiple .kwe file found! using the first one')
%       end
%       obj.triggerFilename = fullfile(obj.recordingDir, triggerFile.name);
      
      if exist([obj.recordingDir filesep 'metaData.mat'],'file') && ~obj.overwriteMetaData
          obj = loadMetaData(obj); %needs recNameHD5
      else
          obj = extractMetaData(obj);
      end
      
      obj.numRecordings = length(obj.info.Groups);
      if obj.numRecordings > 1
          warning('KwikRecording: file contains multiple recordings.')
      end
      
      obj.recNameHD5 = cell(1, obj.numRecordings);
      for k = 1:obj.numRecordings
          obj.recNameHD5{k} = obj.info.Groups(k).Name;
      end
     
      %layout
      obj=obj.loadChLayout;
      if isempty(obj.chLayoutNumbers)
          if obj.totalChannels<=32
              obj.layoutName='layout_300_6x6_FlexMEA';
              obj.electrodePitch=300;
          elseif obj.totalChannels<=60
              obj.layoutName='layout_200_8x8.mat';
              obj.electrodePitch=200;
          elseif obj.totalChannels<=120
              obj.layoutName='layout_100_12x12.mat';
              obj.electrodePitch=100;
          elseif obj.totalChannels<=252
              obj.layoutName='layout_100_16x16.mat';
              obj.electrodePitch=100;
          end
          load(obj.layoutName);
          obj.chLayoutNumbers=En;
          obj.chLayoutNames=Ena;
          obj.chLayoutPositions=Enp;
      end  
       obj=obj.configureN2S;
    end
    
    function delete(obj) %do nothing
    end
    
  end
  
  methods
    
    function obj = extractMetaData(obj)
        %a lot of these data come as a vector specifing a value for each \
        %channel. assuming they are the same for all, just the first one 
        %is taken (i.e. time tick, ADZero,RawDataType,ConcersionFactor,
        %HighPassFilterType etc
                   
        if ~strcmp(obj.fullFilename(end-1:end),'h5')
            obj.fullFilename=[obj.fullFilename '.h5'];
        end
        
        %get start date. This currently only works windows. Otherwise, try
        %using the attribute 'Date' in the h5 file.
        dateInTicks=h5readatt(obj.fullFilename,'/Data','DateInTicks'); %This is in .NET date
        dt=System.DateTime(dateInTicks); %create .NET DateTime Struct
        dateInString=char(dt.ToString);
        obj.startDate=datenum(dateInString,'dd/mm/yyyy');
        
        obj.info=h5info(obj.fullFilename, obj.pathToAllRecordings);
        obj.analogInfo = h5info(obj.fullFilename, obj.pathToAnalogStream);
        obj.streamPaths{1}=obj.analogInfo.Groups(1).Name; %should be stream 0 path
        obj.streamPaths{2}=obj.analogInfo.Groups(2).Name; %should be stream 1 path
        obj.streamPaths{3}=obj.analogInfo.Groups(3).Name; %should be stream 2 path
        
        %get streams' numbers and paths (for raw electrode, digital and aux
        %streams. Usually it's 0,1,2 but just to make sure
        obj.streamsSubTypes={h5readatt(obj.fullFilename,obj.streamPaths{1},'DataSubType'),h5readatt(obj.fullFilename,obj.streamPaths{2},'DataSubType'),h5readatt(obj.fullFilename,obj.streamPaths{3},'DataSubType')};
        obj.electrodeStreamNum=find(ismember(obj.streamsSubTypes,obj.defaultRawDataStreamName))-1; %'Electrode';'Auxiliary';'Digital';
        obj.auxStreamNum=find(ismember(obj.streamsSubTypes,obj.defaultAnalogDataStreamName))-1;
        obj.digitalStreamNum=find(ismember(obj.streamsSubTypes,obj.defaultDigitalDataStreamName))-1;
       
        obj.pathToRawDataStreamGroup=obj.streamPaths{obj.electrodeStreamNum+1}; %these are without '/' ending 
        obj.pathToDigitalDataStreamGroup=obj.streamPaths{obj.digitalStreamNum+1};
        obj.pathToAuxDataStreamGroup=obj.streamPaths{obj.auxStreamNum+1};
        
        obj.lengthInfo = h5info(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelData']);
        
        obj.electrodeInfoChannel=h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/InfoChannel']);
%         digitalInfoChannel
%         auxInfoChannel
        obj.MicrovoltsPerAD = double(obj.electrodeInfoChannel.ConversionFactor); %this is a nx1 array (n channels)
        obj.ZeroADValue=double(obj.electrodeInfoChannel.ADZero);
      
      obj.dataLength = obj.lengthInfo.Dataspace.Size(1);
      obj.totalChannels=obj.lengthInfo.Dataspace.Size(2); 
      obj.channelNumbers = 1:length(obj.MicrovoltsPerAD);
      obj.channelNames =  obj.electrodeInfoChannel.Label;
      %n2s configuration at the end of class constructor
%     obj.channelNames = cellfun(@(x) num2str(x), mat2cell(obj.channelNumbers,1,ones(1,numel(obj.channelNumbers))),'UniformOutput',0); 
      obj.analogChannelNumbers=1; %only one non-electrode analog channel - the aux stream
      
      obj.sample_ms = double(obj.electrodeInfoChannel.Tick(1))/1000;
      obj.samplingFrequency = 1e3/obj.sample_ms; %Assuming all chanels are the same
      obj.recordingDuration_ms=obj.sample_ms*obj.dataLength;
%         disp('Extracting time stamp information...');
        obj.timestamps = double(h5read(obj.fullFilename, [obj.pathToRawDataStreamGroup '/ChannelDataTimeStamps']));
%         disp('... done');

%       obj.globalStartTime = double(h5readatt(obj.fullFilename, obj.recNameHD5{1}, 'start_time'));

%       try
%         obj.recordingDuration_ms = double(h5readatt(obj.fullFilename,[obj.recNameHD5{1} '/data'], 'valid_samples'));
%         obj.recordingDuration_ms = 1000 * obj.recordingDuration_ms ./ obj.samplingFrequency;
%         obj.recordingDuration_ms = max(obj.recordingDuration_ms);
%       catch
%         try
%           obj.recordingDuration_ms = double(h5readatt(obj.fullFilename, '/', 'recordingDuration'));
%         catch
%           obj.recordingDuration_ms = 0;
%         end
%       end     
      
      obj.unit=obj.electrodeInfoChannel.Unit(1);
      obj.exponent=obj.electrodeInfoChannel.Exponent; 
      rawDataType=char(obj.electrodeInfoChannel.RawDataType(1));
      databit=char(obj.electrodeInfoChannel.ADCBits(1));
      if strcmp(rawDataType,'Int'), rawDataType='int'; end
      if databit==24, databit=32; end %MCs ADC works in 24 bits quantization, but stores in 32 bit format (Try to get aroung this)
      obj.datatype = [rawDataType '32'];                
                
      disp('saving meta data');
      obj.saveMetaData;
    end
    function obj = configureN2S(obj)
    % This function creats the n2s transormation.
    % n2s is used to find what is the MSC's channel number that corresponds to
    % the channel number that is described in chLayoutNumbers.
    % The usage is as follows: if you want to get the raw of data from
    % channel m (m being the number as it apears in chLayoutNumbers), you take
    % the n2s(m)'th row from ChannelData
        
        obj.n2s=zeros(obj.totalChannels,1);
        for k=1:obj.totalChannels
            channelKLabelIndex=find(obj.chLayoutNumbers==k);
            obj.n2s(k)=find(strcmp(obj.electrodeInfoChannel.Label,obj.chLayoutNames{channelKLabelIndex}));
        end
    end
  end

end