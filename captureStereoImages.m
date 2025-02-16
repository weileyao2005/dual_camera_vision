function captureStereoImages()
    % 创建保存目录
    mkdir('calib_images/left');
    mkdir('calib_images/right');

    % 初始化摄像头
    try
        % 设备1 (ID=1): Integrated Camera
        vidLeft = videoinput('winvideo', 1, 'YUY2_640x480');
        src1 = getselectedsource(vidLeft);
        
        % 设备2 (ID=2): C920
        vidRight = videoinput('winvideo', 2, 'MJPG_640x480');
        src2 = getselectedsource(vidRight);

        % 自动设置帧率
        set_cam_framerate(src1);
        set_cam_framerate(src2);
        
        % 显示设置信息
        fprintf('左相机帧率: %s\n', get(src1, 'FrameRate'));
        fprintf('右相机帧率: %s\n', get(src2, 'FrameRate'));
        
    catch ME
        error('摄像头初始化失败: %s', ME.message);
    end

    % 创建GUI界面
    fig = uifigure('Name', '双目标定采集', 'Position', [100 100 350 180]);
    
    % 添加实时预览按钮
    uibutton(fig, 'push',...
        'Position', [20 120 120 22],...
        'Text', '开启预览',...
        'ButtonPushedFcn', @(src,event) start_preview(vidLeft, vidRight));
    
    % 添加捕获按钮
    uibutton(fig, 'push',...
        'Position', [160 120 120 22],...
        'Text', '捕获图像',...
        'ButtonPushedFcn', @(src,event) capture_images(vidLeft, vidRight));
    
    % 添加状态显示
    txt = uitextarea(fig,...
        'Position', [20 80 260 30],...
        'Value', sprintf('当前分辨率:\n左相机: 640x480 (YUY2)  右相机: 640x480 (MJPG)'));
    
    % 设置关闭回调
    fig.CloseRequestFcn = @(src,event) close_app(src, vidLeft, vidRight);
end

function start_preview(vidLeft, vidRight)
    % 创建预览窗口
    previewFig = figure('Name', '双相机预览', 'Position', [100 200 800 400]);
    
    % 左相机预览
    subplot(1,2,1);
    h1 = preview(vidLeft);
    title('左相机 (Integrated Camera)');
    
    % 右相机预览
    subplot(1,2,2);
    h2 = preview(vidRight);
    title('右相机 (C920)');
    
    % 设置预览窗口关闭回调
    previewFig.CloseRequestFcn = @(src,event) stop_preview(src, vidLeft, vidRight);
end

function stop_preview(fig, vidLeft, vidRight)
    closepreview(vidLeft);
    closepreview(vidRight);
    delete(fig);
end

function capture_images(vidLeft, vidRight)
    persistent count
    if isempty(count)
        count = 0;
    end
    
    try
        % 同步捕获
        imgLeft = getsnapshot(vidLeft);
        imgRight = getsnapshot(vidRight);
        
        % 转换YUY2到RGB
        imgLeft = ycbcr2rgb(imgLeft);
        
        % 生成文件名
        count = count + 1;
        timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS-FFF');
        leftPath = fullfile('calib_images', 'left', sprintf('left_%03d_%s.jpg', count, timestamp));
        rightPath = fullfile('calib_images', 'right', sprintf('right_%03d_%s.jpg', count, timestamp));
        
        % 保存图像
        imwrite(imgLeft, leftPath, 'Quality', 95);
        imwrite(imgRight, rightPath, 'Quality', 95);
        
        fprintf('成功捕获第%d组图像: %s\n', count, timestamp);
    catch ME
        errordlg(sprintf('捕获失败: %s', ME.message));
    end
end

function close_app(fig, vidLeft, vidRight)
    try
        if isvalid(vidLeft), delete(vidLeft); end
        if isvalid(vidRight), delete(vidRight); end
        delete(fig);
    catch
        delete(fig);
    end
end

function set_cam_framerate(src)
    % 自动设置摄像头帧率
    if isprop(src, 'FrameRate')
        availableRates = set(src, 'FrameRate');
        
        % 优先选择30 FPS
        if any(cellfun(@(x) contains(x, '30'), availableRates))
            src.FrameRate = '30.0000';
        else
            % 使用第一个可用帧率
            src.FrameRate = availableRates{1};
            warning('使用默认帧率: %s', src.FrameRate);
        end
        
        % 验证设置结果
        if ~strcmp(src.FrameRate, '30.0000')
            fprintf('注意：实际设置帧率为 %s\n', src.FrameRate);
        end
    end
end